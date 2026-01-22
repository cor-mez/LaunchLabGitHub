//
//  TelemetryDump.swift
//  LaunchLab
//
//  Offline telemetry export utility
//

import Foundation

enum TelemetryDump {

    static func dumpCSV(
        filename: String = defaultFilename()
    ) {

        let events = TelemetryRingBuffer.shared.snapshot()
        guard !events.isEmpty else {
            print("⚠️ TelemetryDump: buffer empty")
            return
        }

        var lines: [String] = []
        lines.reserveCapacity(events.count + 1)

        lines.append("timestamp,phase,code,valueA,valueB")

        for e in events {
            lines.append(
                String(
                    format: "%.6f,%@,%d,%.6f,%.6f",
                    e.timestamp,
                    e.phase.rawValue,
                    e.code,
                    e.valueA,
                    e.valueB
                )
            )
        }

        let csv = lines.joined(separator: "\n")

        let url = documentsDirectory()
            .appendingPathComponent(filename)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            print("📤 TelemetryDump written → \(url.path)")
        } catch {
            print("❌ TelemetryDump failed: \(error)")
        }
    }

    private static func documentsDirectory() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
    }

    private static func defaultFilename() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "rs_telemetry_\(df.string(from: Date())).csv"
    }
}
