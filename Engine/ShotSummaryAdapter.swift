//
//  ShotSummaryAdapter.swift
//  LaunchLab
//
//  Engine adapter: ShotLifecycleRecord → EngineShotSummary
//  Authority-only mapping (no observational leakage).
//

import Foundation

enum ShotSummaryAdapter {

    static func makeEngineSummary(
        from record: ShotLifecycleRecord,
        ballSpeedMPH: Double?
    ) -> EngineShotSummary {

        EngineShotSummary(
            shotId: UUID(),
            startTimestamp: record.startTimestamp,
            impactTimestamp: record.impactTimestamp,
            endTimestamp: record.endTimestamp,

            // Legacy field retained for compatibility.
            // Intentionally empty: motion density is observational,
            // not owned by the authority spine.
            motionDensitySummary: "",

            refused: record.refused,
            refusalReason: record.refusalReason.map { stringify($0) },
            finalState: record.finalState.rawValue,
            ballSpeedMPH: ballSpeedMPH
        )
    }

    // -----------------------------------------------------------------
    // MARK: - Refusal Reason Serialization
    // -----------------------------------------------------------------

    private static func stringify(_ reason: RefusalReason) -> String {
        switch reason {

        case .insufficientConfidence:
            return "insufficient_confidence"

        case .insufficientMotion:
            return "insufficient_motion"

        case .markerLost:
            return "marker_lost"

        case .ambiguousDetection:
            return "ambiguous_detection"

        case .lifecycleTimeout:
            return "lifecycle_timeout"

        case .postImpactTimeout:
            return "post_impact_timeout"
        }
    }
}
