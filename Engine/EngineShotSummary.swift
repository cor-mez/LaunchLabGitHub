//
//  EngineShotSummary.swift
//  LaunchLab
//
//  Engine-level immutable shot summary (V1)
//  Motion-first, post-validation only
//

import Foundation

struct EngineShotSummary {

    let shotId: UUID

    let startTimestamp: Double
    let impactTimestamp: Double?
    let endTimestamp: Double

    let motionDensitySummary: String

    let refused: Bool
    let refusalReason: String?

    let finalState: String

    // Optional metrics
    let ballSpeedMPH: Double?
}
