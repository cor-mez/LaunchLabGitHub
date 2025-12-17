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

    // ------------------------------------------------------------------
    // IMPACT-CENTERED DYNAMIC OBSERVABILITY (ICDO) — LOG ONLY
    // ------------------------------------------------------------------

    private var lastMotionPxPerSec: Double?
    private var lastCentroid: SIMD2<Double>?
    private var impactWindowActive = false
    private var impactStartTimeSec: Double?

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
        print(message)
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

        guard snapshot.isValid else {
            let reason: String
            if snapshot.stalenessSec > config.maxStalenessSec {
                reason = "stale \(fmt(snapshot.stalenessSec))s"
            } else if snapshot.spanSec > config.maxSpanSec {
                reason = "span \(fmt(snapshot.spanSec))s"
            } else {
                reason = "insufficient frames"
            }

            logRSWindow(.windowInvalid(reason: reason),
                        "[RSWINDOW] invalid \(reason)")
            return
        }

        logRSWindow(
            .windowReady(count: snapshot.frameCount),
            "[RSWINDOW] ready frames=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec))s"
        )

        // ------------------------------------------------------------------
        // 4️⃣ ICDO — Impact-Centered Dynamic Observability (LOG ONLY)
        // ------------------------------------------------------------------

        if DebugProbe.isEnabled(.capture) {

            let centroid = SIMD2<Double>(
                Double(ballCenter2D.x),
                Double(ballCenter2D.y)
            )

            let motionDelta = (lastMotionPxPerSec != nil && motionPxPerSec != nil)
                ? abs(motionPxPerSec! - lastMotionPxPerSec!)
                : nil

            let centroidJump = (lastCentroid != nil)
                ? simd_length(centroid - lastCentroid!)
                : nil

            // Candidate start (no thresholds — multi-signal presence only)
            if !impactWindowActive,
               motionDelta != nil || centroidJump != nil {

                impactWindowActive = true
                impactStartTimeSec = timestampSec

                print("[IMPACT] candidate start frame=\(snapshot.frameCount)")
                print("[IMPACT] trigger signals=" +
                      "motionΔ=\(fmt(motionDelta)) " +
                      "centroidJump=\(fmt(centroidJump))")
            }

            // During candidate window
            if impactWindowActive {

                let spanMs = (timestampSec - (impactStartTimeSec ?? timestampSec)) * 1000.0

                print("[IMPACT] candidate span_ms=\(fmt(spanMs))")

                // Geometry observation (pre/during/post will be inferred offline)
                print("[IMPACT][GEOM] radius_px=\(fmt(ballRadiusPx)) " +
                      "frameCount=\(snapshot.frameCount)")

                // Confidence continuity
                print("[IMPACT][CONF] ballLock=\(fmt(smoothedBallLockCount)) " +
                      "rsWindowValid=\(snapshot.isValid)")

                // Rolling-shutter placeholders (no assumptions)
                print("[RS] shear_peak=n/a temporal_asymmetry=n/a scanline_motion_profile=n/a")
            }

            // End window automatically when motion settles (no thresholds)
            if impactWindowActive,
               motionPxPerSec != nil,
               lastMotionPxPerSec != nil,
               abs(motionPxPerSec! - lastMotionPxPerSec!) < 1e-6 {

                impactWindowActive = false
                impactStartTimeSec = nil
                print("[IMPACT] candidate end")
            }

            lastMotionPxPerSec = motionPxPerSec
            lastCentroid = centroid
        }

        // ------------------------------------------------------------------
        // 5️⃣ Minimal RS-PnP solve + pose observation (unchanged)
        // ------------------------------------------------------------------

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

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.3f", v)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func fmt(_ v: Float) -> String {
        String(format: "%.2f", v)
    }
}
