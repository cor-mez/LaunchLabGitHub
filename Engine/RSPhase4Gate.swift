//
//  RSPhase4Gate.swift
//  LaunchLab
//
//  PHASE 4 — Window-level RS gating (OBSERVABILITY ONLY)
//
//  ROLE (STRICT):
//  - Classify Phase-3 RS windows as pass/fail
//  - NO authority
//  - NO shot decisions
//  - Deterministic + explainable
//

import Foundation

enum RSPhase4Verdict: String {
    case pass = "pass"
    case fail = "fail"
}

struct RSPhase4Gate {

    static func evaluate(_ window: RSWindowObservation) -> RSPhase4Verdict {

        // -----------------------------------------------------
        // 1. Minimum data sufficiency
        // -----------------------------------------------------
        guard window.frameCount >= 3 else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x91, // FAIL: insufficient frames
                valueA: window.zmaxPeak,
                valueB: window.structureConsistency
            )
            return .fail
        }

        // -----------------------------------------------------
        // 2. Require some structured RS presence
        // -----------------------------------------------------
        guard window.structuredFrameCount >= 2 else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x91, // FAIL: no structured frames
                valueA: window.zmaxPeak,
                valueB: window.structureConsistency
            )
            return .fail
        }

        // -----------------------------------------------------
        // 3. Absolute RS shear threshold (physics-based)
        // -----------------------------------------------------
        guard window.zmaxPeak >= 0.015 else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x91, // FAIL: shear too weak
                valueA: window.zmaxPeak,
                valueB: window.structureConsistency
            )
            return .fail
        }

        // -----------------------------------------------------
        // 4. Structure consistency (reject uniform flicker)
        // -----------------------------------------------------
        guard window.structureConsistency >= 0.45 else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x91, // FAIL: low structure consistency
                valueA: window.zmaxPeak,
                valueB: window.structureConsistency
            )
            return .fail
        }

        // -----------------------------------------------------
        // PASS: physically plausible RS launch envelope
        // -----------------------------------------------------
        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x90, // PASS
            valueA: window.zmaxPeak,
            valueB: window.structureConsistency
        )
        return .pass
    }
}
