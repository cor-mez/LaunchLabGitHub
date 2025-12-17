//
//  RSPnP_V1.swift
//  LaunchLab
//
//  Minimal RS-PnP bridge (observational only)
//  - refusal-first
//  - no smoothing
//  - no retries
//  - no downstream pose consumption
//

import Foundation
import CoreGraphics
import simd

// MARK: - Config

struct RSPnPConfig: Equatable {
    var minFrames: Int = 3
    var requireRowTiming: Bool = false
}

// MARK: - Outcome Types

enum RSPnPSkipReason: Equatable {
    case insufficientFrames(count: Int, min: Int)
    case invalidWindow(reason: String)
    case alreadyProcessed(windowLastTimestamp: Double)

    var logString: String {
        switch self {
        case .insufficientFrames(let c, let m):
            return "skipped insufficientFrames \(c)<\(m)"
        case .invalidWindow(let r):
            return "skipped invalidWindow \(r)"
        case .alreadyProcessed(let t):
            return "skipped alreadyProcessed t=\(String(format: "%.6f", t))"
        }
    }
}

enum RSPnPFailure: Equatable {
    case missingRowTiming
    case nonFiniteInput
    case notImplementedV1

    var logString: String {
        switch self {
        case .missingRowTiming: return "failure missingRowTiming"
        case .nonFiniteInput:   return "failure nonFiniteInput"
        case .notImplementedV1: return "failure notImplementedV1"
        }
    }
}

enum RSPnPOutcome: Equatable {
    case skipped(RSPnPSkipReason)
    case failure(RSPnPFailure)
    case success(
        pose: simd_double4x4,
        residual: Double,
        conditioning: Double
    )
}

// MARK: - RS-PnP Bridge

/// V1 bridge solver:
/// - accepts an RSWindowSnapshot
/// - attempts solve ONLY when snapshot is valid + frameCount >= minFrames
/// - returns explicit success / failure / skipped
/// - logs on state transitions only
final class RSPnPBridgeV1 {
    
    // MARK: - Config
    
    private let config: RSPnPConfig
    
    // Pose stability observer (OBSERVATIONAL ONLY)
    private let poseStability = RSPnPPoseStabilityCharacterizer(
        config: RSPnPPoseStabilityConfig(
            historySize: 20,
            minSamplesForCorrelation: 8,
            logEveryNSuccesses: 1
        )
    )
    
    // MARK: - Logging State (anti-spam)
    
    private enum LogState: Equatable {
        case idleSkip(String)
        case attempting
        case success
        case failure(String)
    }
    
    private var logState: LogState = .idleSkip("startup")
    
    // Prevent redundant attempts on identical window end timestamps
    private var lastProcessedWindowLastT: Double? = nil
    
    // MARK: - Init
    
    init(config: RSPnPConfig = RSPnPConfig()) {
        self.config = config
    }
    
    // MARK: - Entry
    
    func process(window: RSWindowSnapshot) -> RSPnPOutcome {
        
        guard window.frameCount >= config.minFrames else {
            let res: RSPnPOutcome =
                .skipped(.insufficientFrames(
                    count: window.frameCount,
                    min: config.minFrames
                ))
            logTransitionIfNeeded(result: res, window: window)
            return res
        }
        
        guard window.isValid else {
            let res: RSPnPOutcome =
                .skipped(.invalidWindow(
                    reason: "valid=false count=\(window.frameCount)"
                ))
            logTransitionIfNeeded(result: res, window: window)
            return res
        }
        
        if let lastT = window.frames.last?.timestampSec,
           let prev = lastProcessedWindowLastT,
           abs(lastT - prev) < 1e-9 {
            
            let res: RSPnPOutcome =
                .skipped(.alreadyProcessed(
                    windowLastTimestamp: lastT
                ))
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
    
    // MARK: - Minimal Solve (V1)
    
    private func solveV1(window: RSWindowSnapshot) -> RSPnPOutcome {
        
        // ------------------------------------------------------------
        // Placeholder V1 implementation — explicit failure
        // ------------------------------------------------------------
        let result: RSPnPOutcome = .failure(.notImplementedV1)
        
        // ------------------------------------------------------------
        // Pose Stability Observation (NO POSE PATH)
        // ------------------------------------------------------------
        poseStability.observeNoPose(
            nowSec: window.snapshotTimeSec,
            reason: "not_implemented_v1"
        )
        
        return result
    }
    
    // MARK: - Logging Helpers
    
    private func logAttemptIfNeeded(window: RSWindowSnapshot) {
        guard DebugProbe.isEnabled(.capture) else { return }
        if logState != .attempting {
            logState = .attempting
            print("[RSPNP] attempted frames=\(window.frameCount)")
        }
    }
    
    private func logTransitionIfNeeded(
        result: RSPnPOutcome,
        window: RSWindowSnapshot
    ) {
        guard DebugProbe.isEnabled(.capture) else { return }
        
        switch result {
            
        case .skipped(let r):
            if logState != .idleSkip(r.logString) {
                logState = .idleSkip(r.logString)
                print("[RSPNP] \(r.logString)")
            }
            
        case .failure(let f):
            if logState != .failure(f.logString) {
                logState = .failure(f.logString)
                print("[RSPNP] \(f.logString)")
            }
            
        case .success(_, let residual, let conditioning):
            if logState != .success {
                logState = .success
                
                // Existing summary log
                print(
                    "[RSPNP] success residual=\(String(format: "%.4f", residual)) " +
                    "cond=\(String(format: "%.4f", conditioning))"
                )
                
                // 🔍 NEW: explicit solver-boundary confirmation
                print(
                    "[DEBUG][RSPNP] solver success " +
                    "frames=\(window.frameCount) " +
                    "residual=\(String(format: "%.4f", residual)) " +
                    "cond=\(String(format: "%.4f", conditioning))"
                )
            }
        }
    }
}
