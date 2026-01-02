//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Central engine coordinator (V1.7)
//
//  Presence is strict.
//  Impact confirmation detects regime change.
//  Ballistic motion validity runs ONLY post-impact.
//  Motion is anchored + integrated before judgment.
//

import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import Metal

@MainActor
final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    // MARK: - Core Systems

    let mode     = DotTestMode.shared
    let detector = MetalDetector.shared
    let ballLock = BallLockV0()

    private let presenceGate      = PresenceAuthorityGate()
    private let roiAnchor         = AnchoredROICenter()
    private let motionIntegrator  = MotionAnchorIntegrator()
    private let motionGate        = MotionValidityGate()
    private let continuityLatch   = PresenceContinuityLatch()
    private let kineticGate       = KineticEligibilityGate()
    private let impactConfirmGate = ImpactConfirmationGate()

    /// Inject this from camera setup
    var cameraStabilityController: CameraStabilityController?

    private let rawMotionLogger       = RawMotionLogger()
    private let impactSignatureLogger = ImpactSignatureLogger()

    private let separationObserver = SeparationMotionObserver()
    private var activeSeparationROI: SeparationAttentionROI?

    // MARK: - Frame State

    private var frameIndex = 0
    private let detectionInterval = 3

    internal(set) var lastROI: CGRect = .zero
    internal(set) var lastFull: CGSize = .zero

    // MARK: - Motion Phase

    private enum MotionPhase {
        case idle
        case postImpact
    }

    private var motionPhase: MotionPhase = .idle

    // MARK: - Raw Motion Memory

    private var lastCenter: CGPoint?
    private var lastTimestampSec: Double?

    private init() {}

    // MARK: - Frame Entry

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }
        guard mode.isArmedForDetection else { return }

        // 🚫 Do nothing until optics are stable
        if let cam = cameraStabilityController, !cam.isStable {
            return
        }

        let t = CMTimeGetSeconds(timestamp)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }

        lastFull = CGSize(width: w, height: h)

        let roiSize: CGFloat = 200
        let roi = CGRect(
            x: lastFull.width  * 0.5 - roiSize * 0.5,
            y: lastFull.height * 0.5 - roiSize * 0.5,
            width: roiSize,
            height: roiSize
        ).integral

        lastROI = roi
        detectGPU(pb: pb, roi: roi, timestampSec: t)
    }

    // MARK: - GPU Detection

    private func detectGPU(
        pb: CVPixelBuffer,
        roi: CGRect,
        timestampSec: Double
    ) {

        detector.prepareFrameY(pb, roi: roi, srScale: mode.srScale)
        let scored = detector.gpuFast9ScoredCornersY()
        let points = scored.map { $0.point }

        var confidence: Float = 0
        var rawCenter: CGPoint?

        if let cluster = ballLock.findBallCluster(from: points) {
            confidence = Float(cluster.count)
            rawCenter = cluster.center

            rawMotionLogger.log(
                timestampSec: timestampSec,
                center: cluster.center,
                clusterCount: cluster.count
            )
        } else {
            rawMotionLogger.logUnlocked(timestampSec: timestampSec)
            resetAllTransientState()
            return
        }

        // --------------------------------------------------
        // Instantaneous motion (RAW)
        // --------------------------------------------------

        var instantaneousPxPerSec: Double = 0

        if let c = rawCenter,
           let lastC = lastCenter,
           let lastT = lastTimestampSec {

            let dt = timestampSec - lastT
            if dt > 0 {
                instantaneousPxPerSec = hypot(
                    Double(c.x - lastC.x),
                    Double(c.y - lastC.y)
                ) / dt
            }
        }

        lastCenter = rawCenter
        lastTimestampSec = timestampSec

        // --------------------------------------------------
        // Presence (strict)
        // --------------------------------------------------

        let spatialMask = computeSpatialMask(pb: pb, roi: roi)

        let presenceDecision = presenceGate.update(
            PresenceAuthorityInput(
                timestampSec: timestampSec,
                ballLockConfidence: confidence,
                center: rawCenter,
                speedPxPerSec: instantaneousPxPerSec,
                spatialMask: spatialMask
            )
        )

        guard presenceDecision == .present,
              let detectedCenter = rawCenter else {
            resetAllTransientState()
            return
        }

        // --------------------------------------------------
        // Phase A — Impact confirmation
        // --------------------------------------------------

        if motionPhase == .idle {

            let confirmed = impactConfirmGate.update(
                presenceOk: true,
                center: detectedCenter,
                instantaneousPxPerSec: instantaneousPxPerSec
            )

            if confirmed {
                continuityLatch.latch()
                motionGate.reset()
                motionPhase = .postImpact
            }

            return
        }

        // --------------------------------------------------
        // ROI anchoring + integration
        // --------------------------------------------------

        let anchoredCenter = roiAnchor.update(with: detectedCenter)
        motionIntegrator.setAnchorIfNeeded(anchoredCenter)

        guard let integrated = motionIntegrator.update(
            center: anchoredCenter,
            timestampSec: timestampSec
        ) else {
            return
        }

        // --------------------------------------------------
        // Phase B — Ballistic validity
        // --------------------------------------------------

        let motionDecision = motionGate.update(
            center: anchoredCenter,
            velocityPx: integrated.direction,
            speedPxPerSec: integrated.speedPxPerSec
        )

        guard motionDecision == .valid else { return }

        kineticGate.observe(
            speedPxPerSec: integrated.speedPxPerSec,
            velocityPx: integrated.direction
        )

        let separationAllowed =
            continuityLatch.isActive && kineticGate.isEligible

        if separationAllowed,
           activeSeparationROI == nil {

            activeSeparationROI = SeparationAttentionROI.make(
                impactCenter: anchoredCenter,
                direction: integrated.direction,
                fullSize: lastFull
            )

            separationObserver.reset()
            Log.info(.shot, "PHASE separation_roi_armed")
        }

        if let roiB = activeSeparationROI, separationAllowed {

            let sep = separationObserver.observe(
                center: anchoredCenter,
                velocityPx: integrated.direction,
                expectedDirection: roiB.direction
            )

            switch sep {
            case .coherent(let frames):
                Log.info(.shot, "PHASE separation_coherent frames=\(frames)")
            case .chaotic(let reason):
                Log.info(.shot, "PHASE separation_chaotic reason=\(reason)")
            case .none:
                break
            }
        }
    }

    // MARK: - Spatial Mask

    private func computeSpatialMask(
        pb: CVPixelBuffer,
        roi: CGRect
    ) -> Set<Int> {

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return [] }

        let width = CVPixelBufferGetWidth(pb)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        var mask = Set<Int>()
        let threshold: UInt8 = 90

        for y in Int(roi.minY)..<Int(roi.maxY) {
            let row = base.advanced(by: y * bytesPerRow)
            for x in Int(roi.minX)..<Int(roi.maxX) {
                let lum = row.load(fromByteOffset: x, as: UInt8.self)
                if lum < threshold {
                    mask.insert((y * width) + x)
                }
            }
        }

        return mask
    }

    // MARK: - Reset

    private func resetAllTransientState() {
        presenceGate.reset()
        roiAnchor.reset()
        motionIntegrator.reset()
        motionGate.reset()
        continuityLatch.reset()
        kineticGate.reset()
        impactConfirmGate.reset()
        impactSignatureLogger.reset()
        separationObserver.reset()
        activeSeparationROI = nil
        motionPhase = .idle
    }
}
