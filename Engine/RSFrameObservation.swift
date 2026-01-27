//
//  RSFrameObservation.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

struct RSFrameObservation {

    let timestamp: Double
    let zmax: Float
    let structureRatio: Float
    let rowSpanFraction: Float
    let outcome: RSObservationOutcome

    static func observable(
        timestamp: Double,
        zmax: Float,
        structure: Float,
        span: Float
    ) -> RSFrameObservation {
        RSFrameObservation(
            timestamp: timestamp,
            zmax: zmax,
            structureRatio: structure,
            rowSpanFraction: span,
            outcome: .observable
        )
    }

    static func refused(
        _ timestamp: Double,
        _ reason: RSRefusalReason
    ) -> RSFrameObservation {
        RSFrameObservation(
            timestamp: timestamp,
            zmax: 0,
            structureRatio: 0,
            rowSpanFraction: 0,
            outcome: .refused(reason)
        )
    }
}
