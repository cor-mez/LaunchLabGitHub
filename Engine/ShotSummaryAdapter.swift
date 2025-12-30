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
            refusalReason: record.refusalReason?.rawValue,
            finalState: record.finalState.rawValue,
            ballSpeedMPH: ballSpeedMPH
        )
    }
}
