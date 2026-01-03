//
//  DotTestCoordinator.swift
//  LaunchLab
//
//  Impulse-First Shot Authority (STABLE)
//
//  Presence → Impact Impulse → Shot
//

import CoreMedia
import CoreVideo
import CoreGraphics

final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    // Core
    let detector = MetalDetector.shared
    let ballLock = BallLockV0()

    // Gates
    private let presenceGate = PresenceAuthorityGate()
    private let impactLogger = ImpactSignatureLogger()

    // Impulse authority
    private var lastSpeed: Double = 0
    private var impulseFrames: Int = 0
    private let minImpulseDelta: Double = 120.0   // px/s jump (tune later)
    private let requiredImpulseFrames: Int = 1

    // State
    private var lastCenter: CGPoint?
    private var lastTimestamp: Double?

    private let detectionInterval = 2
    private var frameIndex = 0

    private init() {}

    // MARK: - Entry Point (BACKGROUND ONLY)

    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1
        guard frameIndex % detectionInterval == 0 else { return }

        let t = CMTimeGetSeconds(timestamp)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }

        let roi = CGRect(
            x: CGFloat(w) * 0.5 - 100,
            y: CGFloat(h) * 0.5 - 100,
            width: 200,
            height: 200
        ).integral

        detect(pb, roi: roi, time: t)
    }

    // MARK: - Detection

    private func detect(
        _ pb: CVPixelBuffer,
        roi: CGRect,
        time: Double
    ) {

        detector.prepareFrameY(pb, roi: roi, srScale: 1.0)
        let points = detector.gpuFast9ScoredCornersY().map { $0.point }

        guard let cluster = ballLock.findBallCluster(from: points) else {
            resetImpulse()
            return
        }

        let center = cluster.center

        var speed: Double = 0
        if let lastC = lastCenter, let lastT = lastTimestamp {
            let dt = time - lastT
            if dt > 0 {
                let dx = center.x - lastC.x
                let dy = center.y - lastC.y
                speed = hypot(dx, dy) / dt
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
            resetImpulse()
            return
        }

        // -------------------------
        // IMPULSE AUTHORITY
        // -------------------------

        let delta = speed - lastSpeed
        lastSpeed = speed

        if delta >= minImpulseDelta {
            impulseFrames += 1
        } else {
            impulseFrames = 0
        }

        if impulseFrames >= requiredImpulseFrames {
            Log.info(
                .finalShot,
                "IMPULSE Δv=\(Int(delta))px/s speed=\(Int(speed))px/s"
            )
            finalizeShot()
        }
    }

    // MARK: - Finalize

    private func finalizeShot() {
        Log.info(.finalShot, "SHOT CONFIRMED")
        resetAll()
    }

    // MARK: - Reset

    private func resetImpulse() {
        lastSpeed = 0
        impulseFrames = 0
    }

    private func resetAll() {
        lastCenter = nil
        lastTimestamp = nil
        resetImpulse()
        impactLogger.reset()
    }
}
