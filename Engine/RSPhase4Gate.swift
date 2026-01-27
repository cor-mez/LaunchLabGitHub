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

enum RSPhase4Verdict {
    case pass
    case fail
}

struct RSPhase4Gate {

    static func evaluate(_ window: RSWindowObservation) -> RSPhase4Verdict {

        // 1. Minimum data
        guard window.frameCount >= 3 else {
            return .fail
        }

        // 2. Structure present
        guard window.structureConsistency >= 0.4 else {
            return .fail
        }

        // 3. Shear separates from baseline
        guard window.zmaxPeak >= 2.5 * window.zmaxMedian else {
            return .fail
        }

        // 4. Reject pure flicker (but allow wide structured motion)
        if window.wideSpanFraction >= 0.95 &&
           window.structureConsistency < 0.6 {
            return .fail
        }

        return .pass
    }
}
