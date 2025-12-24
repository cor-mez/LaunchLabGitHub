//
//  RSIntegrationV1.swift
//  LaunchLab
//
//  Confidence-gated bridge: BallLock → RSWindow → RS-PnP
//  Observability + correctness first
//

import Foundation
import CoreGraphics
import simd

final class RSIntegrationV1 {

    // MARK: - Config

    struct Config: Equatable {
        var confidenceThreshold: Float = 12.0
        var minFrames: Int = 3
        var windowSize: Int = 4
        var maxStalenessSec: Double = 0.080
        var maxSpanSec: Double = 0.080
        var logTransitionsOnly: Bool = true
    }

    // MARK: - RSWindow Logging State

    private enum RSWindowLogState: Equatable {
        case idle
        case rejectedLowConfidence
        case accepted(count: Int)
        case windowReady(count: Int)
        case windowInvalid(reason: String)
    }

    // MARK: - State Storage

    private var rsWindowLogState: RSWindowLogState = .idle

    // MARK: - Members

    private let config: Config
    private let window: RSWindow
    private let solver: RSPnPBridgeV1

    // Impact-Centered Dynamic Observability (log-only)
    private let icdoModule = ImpactCenteredDynamicObservabilityModule()

    // Pose module (observational only — no downstream use)
    private let rspnpPoseModule = RSPnPMinimalSolveAndPoseStabilityModule(
        config: .init(
            enabled: true,
            confidenceThreshold: 12.0,
            logTransitionsOnly: true
        ),
        poseConfig: .init(
            historySize: 20,
            minSamplesForCorrelation: 8,
            logEveryNSuccesses: 1
        )
    )

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
        self.window = RSWindow()
        self.solver = RSPnPBridgeV1(
            config: RSPnPConfig(
                minFrames: config.minFrames,
                requireRowTiming: false
            )
        )
    }

    // MARK: - RSWindow Logging

    private func logRSWindow(
        _ newState: RSWindowLogState,
        _ message: String
    ) {
        guard DebugProbe.isEnabled(.capture) else { return }
        guard newState != rsWindowLogState else { return }
        rsWindowLogState = newState
        Log.info(.shot, message)
    }

    // MARK: - Ingest (called once per eligible frame)

    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        smoothedBallLockCount: Float,
        motionPxPerSec: Double?
    ) {

        // 1️⃣ Confidence gate
        guard smoothedBallLockCount >= config.confidenceThreshold else {
            logRSWindow(
                .rejectedLowConfidence,
                "[RSWINDOW] rejected conf=\(fmt(smoothedBallLockCount)) < \(fmt(config.confidenceThreshold))"
            )
            return
        }

        // 2️⃣ Feed RSWindow
        window.ingest(
            ballCenter2D: ballCenter2D,
            ballRadiusPx: ballRadiusPx,
            timestampSec: timestampSec,
            confidence: smoothedBallLockCount
        )

        logRSWindow(
            .accepted(count: window.frameCount),
            "[RSWINDOW] accepted t=\(fmt(timestampSec)) count=\(window.frameCount)"
        )

        // 3️⃣ Snapshot + validity gate
        let snapshot = window.snapshot(nowSec: timestampSec)

        // ICDO observation (log only, no gating)
        icdoModule.observe(
            ICDOObservation(
                timestampSec: timestampSec,
                frameIndex: snapshot.frameCount,
                centroidPx: SIMD2<Double>(
                    Double(ballCenter2D.x),
                    Double(ballCenter2D.y)
                ),
                ballRadiusPx: Double(ballRadiusPx),
                compactness: nil,
                densityCount: nil,
                fast9Points: nil,
                scanlineMotionProfile: nil,
                ballLockConfidence: smoothedBallLockCount,
                mdgAccepted: nil,
                rsWindowValid: snapshot.isValid,
                rowTiming: snapshot.frames.last?.rowTiming
            )
        )

        guard snapshot.isValid else {
            let reason: String
            if snapshot.stalenessSec > config.maxStalenessSec {
                reason = "stale \(fmt(snapshot.stalenessSec))s"
            } else if snapshot.spanSec > config.maxSpanSec {
                reason = "span \(fmt(snapshot.spanSec))s"
            } else {
                reason = "insufficient frames"
            }

            logRSWindow(
                .windowInvalid(reason: reason),
                "[RSWINDOW] invalid \(reason)"
            )
            return
        }

        logRSWindow(
            .windowReady(count: snapshot.frameCount),
            "[RSWINDOW] ready frames=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec))s"
        )

        // 4️⃣ Minimal RS-PnP solve + pose observation
        rspnpPoseModule.evaluate(
            nowSec: timestampSec,
            ballLockConfidence: smoothedBallLockCount,
            window: snapshot,
            motionPxPerSec: motionPxPerSec,
            solve: { window in
                let outcome = self.solver.process(window: window)
                guard case let .success(pose, residual, conditioning) = outcome else {
                    throw NSError(domain: "RSPnP", code: -1)
                }
                return (pose, residual, conditioning)
            }
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func fmt(_ v: Float) -> String {
        String(format: "%.2f", v)
    }
}
