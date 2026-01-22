//
//  RSObservabilityTriggers.swift
//  LaunchLab
//
//  Converts raw RS metrics into sparse telemetry events.
//  NO strings. NO allocations.
//

import Foundation

enum RSObservabilityTriggers {

    // Event codes (stable ABI)
    static let rsDetected: UInt16 = 100
    static let rsRejected: UInt16 = 101
    static let flickerSuspected: UInt16 = 110

    @inline(__always)
    static func evaluate(
        zScore: Float,
        r2: Float,
        nonUniformity: Float
    ) {
        // Only emit when thresholds crossed
        if zScore > 2.5 && r2 > 0.6 {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: rsDetected,
                valueA: zScore,
                valueB: r2
            )
        } else if nonUniformity > 0.9 {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: flickerSuspected,
                valueA: nonUniformity,
                valueB: zScore
            )
        }
    }
}
