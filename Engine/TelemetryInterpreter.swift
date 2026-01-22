//
//  TelemetryInterpreter.swift
//  LaunchLab
//
//  Converts raw telemetry into human-readable logs.
//  NEVER called from capture / RS threads.
//

import Foundation

enum TelemetryInterpreter {

    static func dumpRecent(limit: Int = 256) {
        let events = TelemetryRingBuffer.shared.snapshot()
        let tail = events.suffix(limit)

        for e in tail {
            print(
                String(
                    format: "[%.4f] %@ code=%d a=%.2f b=%.2f",
                    e.timestamp,
                    e.phase.rawValue.uppercased(),
                    e.code,
                    e.valueA,
                    e.valueB
                )
            )
        }
    }
}
