import Foundation
import CoreGraphics
import simd

// MARK: - RS‑PnP Bridge V1
// IMPORTANT:
// VisionTypes.swift already defines `public struct RSPnP_V1` as the frozen SE3 contract payload.
// This file must NOT declare another `RSPnP_V1` type, so the solver class is named `RSPnPBridgeV1`.

struct RSPnPConfig: Equatable {
    /// Minimum frames required to even attempt a solve.
    var minFrames: Int = 3

    /// If true, fail when any frame lacks rolling shutter metadata.
    /// (Keep false for V1 unless timing is wired.)
    var requireRowTiming: Bool = false

    init(minFrames: Int = 3, requireRowTiming: Bool = false) {
        self.minFrames = max(1, minFrames)
        self.requireRowTiming = requireRowTiming
    }
}

/// Control-flow outcome for the bridge (NOT the frozen SE3 contract payload).
enum RSPnPOutcome: Equatable {
    case success(RSPnPSolution)
    case failure(RSPnPFailure)
    case skipped(RSPnPSkip)
}

struct RSPnPSolution: Equatable {
    let orientation: simd_quatf
    let translation: SIMD3<Float>?
    let residual: Float
    let conditioning: Float?
    let timestampSec: Double
    let frameCount: Int
}

enum RSPnPSkip: Equatable {
    case insufficientWindow(reason: String)
    case invalidWindow(reason: String)
    case insufficientFrames(count: Int, min: Int)
    case alreadyProcessed(windowLastTimestamp: Double)

    var logString: String {
        switch self {
        case .insufficientWindow(let r): return "skipped (insufficient window) \(r)"
        case .invalidWindow(let r): return "skipped (invalid window) \(r)"
        case .insufficientFrames(let c, let m): return "skipped (insufficient frames \(c) < \(m))"
        case .alreadyProcessed(let t): return "skipped (already processed lastT=\(String(format: "%.3f", t)))"
        }
    }
}

enum RSPnPFailure: Equatable {
    case missingRowTiming
    case nonFiniteInput
    case notImplementedV1
    case internalError(String)

    var logString: String {
        switch self {
        case .missingRowTiming: return "failure reason=missingRowTiming"
        case .nonFiniteInput: return "failure reason=nonFiniteInput"
        case .notImplementedV1: return "failure reason=notImplementedV1"
        case .internalError(let s): return "failure reason=internalError(\(s))"
        }
    }
}

/// V1 bridge solver:
/// - accepts an RSWindowSnapshot
/// - attempts solve ONLY when snapshot is valid + frameCount >= minFrames
/// - returns explicit success/failure/skipped
/// - logs on state transitions only
final class RSPnPBridgeV1 {

    private let config: RSPnPConfig

    // Logging state to prevent per-frame spam.
    private enum LogState: Equatable {
        case idleSkip(String)
        case attempting
        case success
        case failure(String)
    }
    private var logState: LogState = .idleSkip("startup")

    // Prevent redundant attempts on identical window end timestamps.
    private var lastProcessedWindowLastT: Double? = nil

    init(config: RSPnPConfig = RSPnPConfig()) {
        self.config = config
    }

    func process(window: RSWindowSnapshot) -> RSPnPOutcome {

        guard window.frameCount >= config.minFrames else {
            let res: RSPnPOutcome = .skipped(.insufficientFrames(count: window.frameCount, min: config.minFrames))
            logTransitionIfNeeded(result: res, window: window)
            return res
        }

        guard window.isValid else {
            let res: RSPnPOutcome = .skipped(.invalidWindow(
                reason: "valid=false count=\(window.frameCount)"
            ))
            logTransitionIfNeeded(result: res, window: window)
            return res
        }

        if let lastT = window.frames.last?.timestampSec,
           let prev = lastProcessedWindowLastT,
           abs(lastT - prev) < 1e-9 {
            let res: RSPnPOutcome = .skipped(.alreadyProcessed(windowLastTimestamp: lastT))
            logTransitionIfNeeded(result: res, window: window)
            return res
        }

        if config.requireRowTiming {
            let missing = window.frames.contains { $0.rowTiming == nil }
            if missing {
                let res: RSPnPOutcome = .failure(.missingRowTiming)
                lastProcessedWindowLastT = window.frames.last?.timestampSec
                logTransitionIfNeeded(result: res, window: window)
                return res
            }
        }

        if window.frames.contains(where: {
            !$0.ballCenter2D.x.isFinite ||
            !$0.ballCenter2D.y.isFinite ||
            !$0.ballRadiusPx.isFinite
        }) {
            let res: RSPnPOutcome = .failure(.nonFiniteInput)
            lastProcessedWindowLastT = window.frames.last?.timestampSec
            logTransitionIfNeeded(result: res, window: window)
            return res
        }

        logAttemptIfNeeded(window: window)

        let result = solveV1(window: window)

        lastProcessedWindowLastT = window.frames.last?.timestampSec
        logTransitionIfNeeded(result: result, window: window)
        return result
    }

    private func solveV1(window: RSWindowSnapshot) -> RSPnPOutcome {
        // Bridge-only V1: correctness + observability.
        // Real RS-PnP implementation plugs in here later.
        return .failure(.notImplementedV1)
    }

    // MARK: - Logging (state transitions only)

    private func logAttemptIfNeeded(window: RSWindowSnapshot) {
        guard DebugProbe.isEnabled(.capture) else { return }
        if logState != .attempting {
            logState = .attempting
            print("[RSPNP] solve attempted count=\(window.frameCount)")
        }
    }

    private func logTransitionIfNeeded(result: RSPnPOutcome, window: RSWindowSnapshot) {
        guard DebugProbe.isEnabled(.capture) else { return }

        switch result {
        case .skipped(let s):
            let key = s.logString
            if logState != .idleSkip(key) {
                logState = .idleSkip(key)
                print("[RSPNP] \(s.logString)")
            }

        case .failure(let f):
            let key = f.logString
            if logState != .failure(key) {
                logState = .failure(key)
                print("[RSPNP] \(f.logString) count=\(window.frameCount)")
            }

        case .success(let sol):
            if logState != .success {
                logState = .success
                print("[RSPNP] success residual=\(fmt(sol.residual)) frames=\(sol.frameCount)")
            }
        }
    }

    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
