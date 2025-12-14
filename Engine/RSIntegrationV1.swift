//
//  RSIntegrationV1.swift
//  LaunchLab
//
//  Confidence-gated bridge: BallLock → RSWindow → RSPnP solver
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

    // MARK: - State

    private enum State: Equatable {
        case cold
        case rejectedLowConfidence
        case accepted(Int)
        case windowReady(Int)
        case solverSkipped(String)
        case solverFailed(String)
        case solverSucceeded
    }

    private var state: State = .cold

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

    // MARK: - Ingest

    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        smoothedBallLockCount: Float
    ) {

        // 1️⃣ Confidence gate
        guard smoothedBallLockCount >= config.confidenceThreshold else {
            log(.rejectedLowConfidence,
                "[RSWINDOW] rejected (confidence < threshold) conf=\(fmt(smoothedBallLockCount))")
            return
        }

        // 2️⃣ Feed RSWindow
        window.ingest(
            ballCenter2D: ballCenter2D,
            ballRadiusPx: ballRadiusPx,            timestampSec: timestampSec,
            confidence: smoothedBallLockCount
        )

        log(.accepted(window.frameCount),
            "[RSWINDOW] accepted frame t=\(fmt(timestampSec)) count=\(window.frameCount)")

        // 3️⃣ Snapshot
        let snapshot = window.snapshot(nowSec: timestampSec)

        guard snapshot.isValid else {
            log(.accepted(snapshot.frameCount),
                "[RSWINDOW] window not ready span=\(fmt(snapshot.spanSec)) stale=\(fmt(snapshot.stalenessSec))")
            return
        }

        log(.windowReady(snapshot.frameCount),
            "[RSWINDOW] window ready count=\(snapshot.frameCount)")

        // 4️⃣ Solver
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

    // MARK: - Logging

    private func log(_ newState: State, _ message: String) {
        guard DebugProbe.isEnabled(.capture) else { return }
        if config.logTransitionsOnly && newState == state { return }
        state = newState
        print(message)
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float)  -> String { String(format: "%.2f", v) }
}
