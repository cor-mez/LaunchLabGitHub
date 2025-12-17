import Foundation
import simd

// MARK: - Config

public struct RSPnPMinimalSolveConfig: Equatable {
    public var enabled: Bool
    public var confidenceThreshold: Float
    public var logTransitionsOnly: Bool

    public init(
        enabled: Bool = true,
        confidenceThreshold: Float = 12.0,
        logTransitionsOnly: Bool = true
    ) {
        self.enabled = enabled
        self.confidenceThreshold = confidenceThreshold
        self.logTransitionsOnly = logTransitionsOnly
    }
}

// MARK: - Module

public final class RSPnPMinimalSolveAndPoseStabilityModule {

    private let solveConfig: RSPnPMinimalSolveConfig
    private let poseObserver: RSPnPPoseStabilityCharacterizer

    private var lastOutcome: String?

    // Pose lifetime tracking (observational only)
    private var poseLifetimeFrames: Int = 0
    private var poseActive: Bool = false

    public init(
        config: RSPnPMinimalSolveConfig,
        poseConfig: RSPnPPoseStabilityConfig
    ) {
        self.solveConfig = config
        self.poseObserver = RSPnPPoseStabilityCharacterizer(config: poseConfig)
    }

    // MARK: - Entry Point

    func evaluate(
        nowSec: Double,
        ballLockConfidence: Float,
        window: RSWindowSnapshot,
        motionPxPerSec: Double?,
        solve: (RSWindowSnapshot) throws -> (pose: simd_double4x4, residual: Double, conditioning: Double)
    ) {

        // ----------------------------
        // Gate 1: Module enabled
        // ----------------------------
        guard solveConfig.enabled else {
            logOnce("[RSPNP] skipped reason=disabled")
            endPoseLifetime(reason: "disabled", nowSec: nowSec)
            return
        }

        // ----------------------------
        // Gate 2: Confidence
        // ----------------------------
        guard ballLockConfidence >= solveConfig.confidenceThreshold else {
            logOnce("[RSPNP] skipped reason=confidence")
            endPoseLifetime(reason: "confidence", nowSec: nowSec)
            return
        }

        // ----------------------------
        // Gate 3: RS-Window validity
        // ----------------------------
        guard window.isValid else {
            logOnce("[RSPNP] skipped reason=window")
            endPoseLifetime(reason: "window", nowSec: nowSec)
            return
        }

        logTransition("[RSPNP] attempted")

        do {
            let out = try solve(window)

            if DebugProbe.isEnabled(.capture) {
                print("[RSPNP] success residual=\(fmt(out.residual)) conditioning=\(fmt(out.conditioning))")
            }

            if !poseActive {
                poseActive = true
                poseLifetimeFrames = 0
            }

            poseLifetimeFrames += 1

            poseObserver.observeSuccess(
                nowSec: nowSec,
                pose: out.pose,
                context: .init(
                    confidence: ballLockConfidence,
                    frameCount: window.frameCount,
                    spanSec: window.spanSec,
                    stalenessSec: window.stalenessSec,
                    motionPx: motionPxPerSec
                )
            )

        } catch {
            if DebugProbe.isEnabled(.capture) {
                print("[RSPNP] failed residual=nan conditioning=nan")
            }

            endPoseLifetime(reason: "solve_failed", nowSec: nowSec)
        }
    }

    // MARK: - Pose Lifetime Handling

    private func endPoseLifetime(reason: String, nowSec: Double) {
        if poseActive {
            if DebugProbe.isEnabled(.capture) {
                print("[POSE] lifetime_frames=\(poseLifetimeFrames)")
            }
        }

        poseActive = false
        poseLifetimeFrames = 0

        poseObserver.observeNoPose(nowSec: nowSec, reason: reason)
    }

    // MARK: - Logging Helpers

    private func logOnce(_ msg: String) {
        if solveConfig.logTransitionsOnly {
            guard lastOutcome != msg else { return }
            lastOutcome = msg
        }
        if DebugProbe.isEnabled(.capture) {
            print(msg)
        }
    }

    private func logTransition(_ msg: String) {
        lastOutcome = msg
        if DebugProbe.isEnabled(.capture) {
            print(msg)
        }
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.4f", v)
    }
}
