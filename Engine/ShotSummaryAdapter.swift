//
//  ShotSummaryAdapter.swift
//  LaunchLab
//
//  Engine adapter: ShotLifecycleRecord → EngineShotSummary
//  AUTHORITY-ONLY mapping.
//  NO observational or measured metric leakage.
//

import Foundation

enum ShotSummaryAdapter {

    static func makeEngineSummary(
        from record: ShotLifecycleRecord
    ) -> EngineShotSummary {

        EngineShotSummary(
            shotId: UUID(),
            startTimestamp: record.startTimestamp,
            impactTimestamp: record.impactTimestamp,
            endTimestamp: record.endTimestamp,
            refused: record.refused,
            refusalReason: record.refusalReason.map { stringify($0) },
            finalState: record.finalState.rawValue
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
