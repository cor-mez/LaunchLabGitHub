//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Central engine coordinator (V1.4)
//
//  Motion-first observation with explicit authority gating.
//  Presence is strict.
//  Motion must be valid before impact can exist.
//  Motion is anchored + integrated before validation.
//  Continuity is latched only on valid impact.
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

    private let presenceGate     = PresenceAuthorityGate()
    private let motionGate       = MotionValidityGate()
    private let motionIntegrator = MotionAnchorIntegrator()
    private let continuityLatch  = PresenceContinuityLatch()
    private let kineticGate      = KineticEligibilityGate()

    private let quietGate     = SceneQuietGate()
    private let authorityGate = ShotAuthorityGate()
    private let lifecycle     = ShotLifecycleController()

    private let rawMotionLogger       = RawMotionLogger()
    private let impactSignatureLogger = ImpactSignatureLogger()

    private let separationObserver = SeparationMotionObserver()
    private var activeSeparationROI: SeparationAttentionROI?

    // MARK: - Frame State

    private var frameIndex = 0
    private let detectionInterval = 3

    internal(set) var lastROI: CGRect = .zero
    internal(set) var lastFull: CGSize = .zero

    // MARK: - Motion Memory (pre-integration)

    private var lastCenter: CGPoint?
    private var lastTimestampSec: Double?

    private init() {}

    // MARK: - Frame Entry

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }
        guard mode.isArmedForDetection else { return }

        let t = CMTimeGetSeconds(timestamp)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }

        lastFull = CGSize(width: w, height: h)

        let roiSize: CGFloat = 100
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
        var center: CGPoint?

        if let cluster = ballLock.findBallCluster(from: points) {
            confidence = Float(cluster.count)
            center = cluster.center

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
        // Instantaneous motion (for Presence only)
        // --------------------------------------------------

        var instantaneousPxPerSec: Double = 0

        if let c = center,
           let lastC = lastCenter,
           let lastT = lastTimestampSec {

            let dt = timestampSec - lastT
            if dt > 0 {
                let dx = Double(c.x - lastC.x)
                let dy = Double(c.y - lastC.y)
                instantaneousPxPerSec = hypot(dx, dy) / dt
            }
        }

        lastCenter = center
        lastTimestampSec = timestampSec

        // --------------------------------------------------
        // Spatial Mask (Y-channel occupancy)
        // --------------------------------------------------

        let spatialMask = computeSpatialMask(pb: pb, roi: roi)

        // --------------------------------------------------
        // Presence (strict, multi-signal)
        // --------------------------------------------------

        let presenceDecision = presenceGate.update(
            PresenceAuthorityInput(
                timestampSec: timestampSec,
                ballLockConfidence: confidence,
                center: center,
                speedPxPerSec: instantaneousPxPerSec,
                spatialMask: spatialMask
            )
        )

        let presenceOk = (presenceDecision == .present)

        if presenceOk {
            motionIntegrator.setAnchorIfNeeded(center)
        } else {
            motionIntegrator.reset()
            motionGate.reset()
            continuityLatch.reset()
            kineticGate.reset()
            impactSignatureLogger.reset()
            separationObserver.reset()
            activeSeparationROI = nil
            return
        }

        // --------------------------------------------------
        // Integrated motion (ANCHOR + INTEGRATE)
        // --------------------------------------------------

        guard let integrated = motionIntegrator.update(
            center: center,
            timestampSec: timestampSec
        ) else {
            return
        }

        // --------------------------------------------------
        // Motion validity (stable, integrated)
        // --------------------------------------------------

        let motionDecision = motionGate.update(
            center: center,
            velocityPx: integrated.direction,
            speedPxPerSec: integrated.speedPxPerSec
        )

        guard motionDecision == .valid else {
            Log.info(.shot, "PHASE motion_invalid reason=\(motionDecision)")
            impactSignatureLogger.reset()
            return
        }

        // --------------------------------------------------
        // Impact signature (safe)
        // --------------------------------------------------

        let impactEvent = impactSignatureLogger.observe(
            timestampSec: timestampSec,
            instantaneousPxPerSec: integrated.speedPxPerSec,
            velocityPx: integrated.direction,
            presenceOk: presenceOk
        )

        if impactEvent != nil {
            continuityLatch.latch()
        }

        continuityLatch.tick()

        // --------------------------------------------------
        // Kinetic eligibility
        // --------------------------------------------------

        kineticGate.observe(
            speedPxPerSec: integrated.speedPxPerSec,
            velocityPx: integrated.direction
        )

        let separationAllowed =
            continuityLatch.isActive && kineticGate.isEligible

        // --------------------------------------------------
        // Separation observability
        // --------------------------------------------------

        if separationAllowed,
           activeSeparationROI == nil {

            activeSeparationROI = SeparationAttentionROI.make(
                impactCenter: center ?? .zero,
                direction: integrated.direction,
                fullSize: lastFull
            )

            separationObserver.reset()
            Log.info(.shot, "PHASE separation_roi_armed")
        }

        if let roiB = activeSeparationROI, separationAllowed {

            let sep = separationObserver.observe(
                center: center,
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

    // MARK: - Spatial Mask (Y Channel)

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
        motionGate.reset()
        motionIntegrator.reset()
        continuityLatch.reset()
        kineticGate.reset()
        impactSignatureLogger.reset()
        separationObserver.reset()
        activeSeparationROI = nil
    }
}
