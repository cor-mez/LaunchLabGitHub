//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Separation-First Shot Authority
//
//  Presence → Impact (observed) → Separation (authoritative)
//

import CoreMedia
import CoreVideo
import CoreGraphics

@MainActor
final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    let detector = MetalDetector.shared
    let ballLock = BallLockV0()

    private let presenceGate = PresenceAuthorityGate()
    private let roiAnchor = AnchoredROICenter()
    private let motionIntegrator = MotionAnchorIntegrator()
    private let motionGate = MotionValidityGate()
    private let separationGate = SeparationAuthorityGate()
    private let impactLogger = ImpactSignatureLogger()
    private let cameraObserver = CameraRegimeObserver()

    private var lastCenter: CGPoint?
    private var lastTimestamp: Double?

    private let detectionInterval = 3
    private var frameIndex = 0

    internal(set) var lastROI: CGRect = .zero
    internal(set) var lastFull: CGSize = .zero

    private init() {}

    // MARK: - Frame Entry

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }

        cameraObserver.observe(pixelBuffer: pb)

        let t = CMTimeGetSeconds(timestamp)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }

        lastFull = CGSize(width: w, height: h)

        let roiSize: CGFloat = 200
        let roi = CGRect(
            x: lastFull.width * 0.5 - roiSize * 0.5,
            y: lastFull.height * 0.5 - roiSize * 0.5,
            width: roiSize,
            height: roiSize
        ).integral

        lastROI = roi
        detect(pb, roi: roi, time: t)
    }

    // MARK: - Detection

    private func detect(_ pb: CVPixelBuffer, roi: CGRect, time: Double) {

        detector.prepareFrameY(pb, roi: roi, srScale: 1.0)
        let points = detector.gpuFast9ScoredCornersY().map { $0.point }

        guard let cluster = ballLock.findBallCluster(from: points) else {
            resetAll()
            return
        }

        let center = cluster.center

        var speed: Double = 0
        var velocity = CGVector.zero

        if let lastC = lastCenter, let lastT = lastTimestamp {
            let dt = time - lastT
            if dt > 0 {
                velocity = CGVector(
                    dx: center.x - lastC.x,
                    dy: center.y - lastC.y
                )
                speed = hypot(velocity.dx, velocity.dy) / dt
            }
        }

        lastCenter = center
        lastTimestamp = time

        let presence = presenceGate.update(
            PresenceAuthorityInput(
                timestampSec: time,
                ballLockConfidence: Float(cluster.count),
                center: center,
                speedPxPerSec: speed,
                spatialMask: []
            )
        )

        guard presence == .present else {
            resetAll()
            return
        }

        // -------------------------
        // Impact (Observed Only)
        // -------------------------

        _ = impactLogger.observe(
            timestampSec: time,
            instantaneousPxPerSec: speed,
            presenceOk: true
        )

        // -------------------------
        // Separation (Authoritative)
        // -------------------------

        let anchored = roiAnchor.update(with: center)
        motionIntegrator.setAnchorIfNeeded(anchored)

        guard let integrated = motionIntegrator.update(
            center: anchored,
            timestampSec: time
        ) else { return }

        let motionDecision = motionGate.update(
            phase: .separation,                 // ✅ FIX
            center: anchored,
            velocityPx: integrated.direction,
            speedPxPerSec: integrated.speedPxPerSec
        )

        guard case .valid = motionDecision else { return }

        let authorized = separationGate.update(
            center: anchored,
            velocityPx: integrated.direction,
            speedPxPerSec: integrated.speedPxPerSec,
            cameraStable: cameraObserver.isStable
        )

        guard authorized else { return }

        Log.info(.shot, "[SHOT] authorized_by_separation")
        resetAll()
    }

    // MARK: - Reset

    private func resetAll() {
        lastCenter = nil
        lastTimestamp = nil
        impactLogger.reset()
        motionGate.reset()
        motionIntegrator.reset()
        roiAnchor.reset()
        separationGate.reset()
        cameraObserver.reset()
    }
}
