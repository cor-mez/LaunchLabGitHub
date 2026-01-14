//
//  ShotSummaryAdapter.swift
//  LaunchLab
//
//  Engine adapter: ShotLifecycleRecord → EngineShotSummary
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
            motionDensitySummary: record.motionDensitySummary,
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
