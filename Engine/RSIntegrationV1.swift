//
//  RSIntegrationV1.swift
//  LaunchLab
//
//  Confidence-gated bridge: BallLock → RSWindow → RS-PnP
//  Observability + correctness first
//

import Foundation
import CoreGraphics

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

    // MARK: - RSWindow Logging State (de-duplication only)

    private enum RSWindowLogState: Equatable {
        case idle
        case rejectedLowConfidence
        case accepted(count: Int)
        case windowReady(count: Int)
        case windowInvalid(reason: String)
    }

    // MARK: - Solver / Integration State

    private enum State: Equatable {
        case cold
        case solverSkipped(String)
        case solverFailed(String)
        case solverSucceeded
    }

    // MARK: - State Storage

    private var state: State = .cold
    private var rsWindowLogState: RSWindowLogState = .idle

    // MARK: - Members

    private let config: Config
    private let window: RSWindow
    private let solver: RSPnPBridgeV1

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

    // MARK: - RSWindow Logging (transition-only)

    private func logRSWindow(
        _ newState: RSWindowLogState,
        _ message: String
    ) {
        guard DebugProbe.isEnabled(.capture) else { return }
        guard newState != rsWindowLogState else { return }

        rsWindowLogState = newState
        print(message)
    }

    // MARK: - Ingest

    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        smoothedBallLockCount: Float
    ) {

        // 1️⃣ Confidence gate
        guard smoothedBallLockCount >= config.confidenceThreshold else {
            logRSWindow(
                .rejectedLowConfidence,
                "[RSWINDOW] rejected (confidence < threshold) conf=\(fmt(smoothedBallLockCount)) < \(fmt(config.confidenceThreshold))"
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
            "[RSWINDOW] accepted frame t=\(fmt(timestampSec)) count=\(window.frameCount) conf=\(fmt(smoothedBallLockCount))"
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

            logRSWindow(
                .windowInvalid(reason: reason),
                "[RSWINDOW] invalid \(reason) count=\(snapshot.frameCount)"
            )
            return
        }

        logRSWindow(
            .windowReady(count: snapshot.frameCount),
            "[RSWINDOW] window ready count=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec))s"
        )

        if DebugProbe.isEnabled(.capture) {
            print("""
            [RSWINDOW][SNAPSHOT]
              frames=\(snapshot.frameCount)
              span=\(fmt(snapshot.spanSec))
              stale=\(fmt(snapshot.stalenessSec))
            """)
        }

        // 4️⃣ RS-PnP (still observability-first)
        let result = solver.process(window: snapshot)

        switch result {
        case .success:
            log(.solverSucceeded, "[RSPNP] success")

        case .failure(let f):
            log(.solverFailed(f.logString), "[RSPNP] \(f.logString)")

        case .skipped(let s):
            log(.solverSkipped(s.logString), "[RSPNP] \(s.logString)")
        }
    }

    // MARK: - Solver Logging

    private func log(_ newState: State, _ message: String) {
        guard DebugProbe.isEnabled(.capture) else { return }
        if config.logTransitionsOnly && newState == state { return }
        state = newState
        print(message)
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func fmt(_ v: Float) -> String {
        String(format: "%.2f", v)
    }
}
