// File: Engine/Logging/RawSessionWriter.swift
//
//  RawSessionWriter.swift
//  LaunchLab
//

import Foundation

final class RawSessionWriter {

    private let framesDirectory: URL
    private let telemetryDirectory: URL
    private let queue = DispatchQueue(label: "com.launchlab.rawsession.writer", qos: .utility)

    init?(sessionDirectory: URL) {
        let fm = FileManager.default
        framesDirectory = sessionDirectory.appendingPathComponent("frames", isDirectory: true)
        telemetryDirectory = sessionDirectory.appendingPathComponent("telemetry", isDirectory: true)

        do {
            if !fm.fileExists(atPath: framesDirectory.path) {
                try fm.createDirectory(at: framesDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            if !fm.fileExists(atPath: telemetryDirectory.path) {
                try fm.createDirectory(at: telemetryDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            return nil
        }
    }

    func write(
        frameIndex: Int,
        yData: Data,
        telemetry: RawSessionEntry
    ) {
        let frameName = String(format: "%05d.y", frameIndex)
        let jsonName = String(format: "%05d.json", frameIndex)

        let frameURL = framesDirectory.appendingPathComponent(frameName)
        let jsonURL = telemetryDirectory.appendingPathComponent(jsonName)

        queue.async {
            do {
                try yData.write(to: frameURL, options: .atomic)

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(telemetry)
                try jsonData.write(to: jsonURL, options: .atomic)
            } catch {
                // Silent failure for logging path.
            }
        }
    }
}
