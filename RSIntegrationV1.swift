//
//  RSIntegrationV1.swift
//  LaunchLab
//
//  Confidence-gated bridge: BallLock (read-only) -> RSWindow -> RSPnP_V1
//  Observability + correctness first. No upstream feedback.
//

import Foundation
import CoreGraphics

/// Minimal bridge layer.
/// Owns RSWindow + RSPnP_V1 and exposes a single `ingest(...)` call per frame.
final class RSIntegrationV1 {

    struct Config: Equatable {
        /// Gate: only accept frames when BallLock confidence >= threshold
        var confidenceThreshold: Float = 12.0

        /// Minimum frames required before RSPnP is even asked
        var minFrames: Int = 3

        /// RSWindow depth
        var windowSize: Int = 4

        /// Max staleness allowed (seconds) before window invalid
        var maxStalenessSec: Double = 0.080

        /// Max span allowed (seconds) across frames in window
        var maxSpanSec: Double = 0.080

        /// Log only on transitions (default true)
        var logTransitionsOnly: Bool = true
    }

    private let config: Config
    private let window: RSWindow
    private let solver: RSPnP_V1

    // Debounce / transition logging
    private enum State: Equatable {
        case cold
        case rejectedLowConfidence
        case acceptedFrame(count: Int)
        case windowReady(count: Int)
        case solveSkipped(String)
        case solveFailed(String)
        case solveSucceeded
    }
    private var state: State = .cold

    init(config: Config = Config()) {
        self.config = config
        self.window = RSWindow(config: .init(
            capacity: config.windowSize,
            maxStalenessSec: config.maxStalenessSec,
            maxSpanSec: config.maxSpanSec
        ))
        self.solver = RSPnP_V1(config: .init(minFrames: config.minFrames, requireRowTiming: false))
    }

    /// Call once per frame *after* BallLock has produced a usable center/radius/confidence.
    /// - Returns: RSPnPResult when attempted; otherwise nil (if not ready / rejected).
    @discardableResult
    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        smoothedBallLockCount: Float
    ) -> RSPnPResult? {

        // Hard gate: confidence
        guard smoothedBallLockCount >= config.confidenceThreshold else {
            logTransition(.rejectedLowConfidence,
                          message: "[RSWINDOW] rejected (confidence < threshold) conf=\(fmt(smoothedBallLockCount)) < \(fmt(config.confidenceThreshold))")
            // Explicitly do NOT recover / interpolate
            return nil
        }

        // Accept into RSWindow
        window.push(
            ballCenter2D: ballCenter2D,
            ballRadiusPx: Float(ballRadiusPx),
            timestampSec: timestampSec,
            confidence: smoothedBallLockCount,
            rowTiming: nil
        )

        logTransition(.acceptedFrame(count: window.frameCount),
                      message: "[RSWINDOW] accepted frame t=\(fmt(timestampSec)) count=\(window.frameCount) conf=\(fmt(smoothedBallLockCount))")

        // Only attempt solve when window says it's valid AND meets min frames
        let snapshot = window.snapshot()
        guard snapshot.isValid else {
            // Only log on transitions
            logTransition(.acceptedFrame(count: snapshot.frameCount),
                          message: "[RSWINDOW] window not ready (invalid) count=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec)) stale=\(fmt(snapshot.stalenessSec))")
            return nil
        }

        logTransition(.windowReady(count: snapshot.frameCount),
                      message: "[RSWINDOW] window ready count=\(snapshot.frameCount) span=\(fmt(snapshot.spanSec))")

        // Ask solver (it will return success/failure/skipped explicitly)
        let res = solver.process(window: snapshot)

        switch res {
        case .success:
            logTransition(.solveSucceeded, message: "[RSPNP] success")
        case .failure(let f):
            logTransition(.solveFailed(f.logString), message: "[RSPNP] \(f.logString)")
        case .skipped(let s):
            logTransition(.solveSkipped(s.logString), message: "[RSPNP] \(s.logString)")
        }

        return res
    }

    // MARK: - Logging

    private func logTransition(_ newState: State, message: String) {
        guard DebugProbe.isEnabled(.capture) else { return }

        if config.logTransitionsOnly {
            guard newState != state else { return }
        }

        state = newState
        print(message)
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float)  -> String { String(format: "%.2f", v) }
}