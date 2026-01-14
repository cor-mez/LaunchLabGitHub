//
//  RollingShutterTimingStats.swift
//  LaunchLab
//
//  Pure instrumentation:
//  Verifies true 240 FPS timing via sample buffer timestamps.
//  NO gating. NO heuristics.
//

import CoreMedia

final class RollingShutterTimingStats {

    private let targetDelta: Double = 1.0 / 240.0
    private let tolerance: Double = 0.0005 // ±0.5 ms

    private var frameCount: Int = 0
    private var windowCount: Int = 0

    private var deltas: [Double] = []

    func record(delta: CMTime) {
        let seconds = delta.seconds
        frameCount += 1
        deltas.append(seconds)

        // Immediate violation logging
        if abs(seconds - targetDelta) > tolerance {
            Log.info(
                .camera,
                String(
                    format: "FPS_DRIFT delta=%.5f expected=%.5f",
                    seconds,
                    targetDelta
                )
            )
        }

        // Windowed summary every 60 frames
        if frameCount % 60 == 0 {
            emitWindow()
        }
    }

    private func emitWindow() {
        guard !deltas.isEmpty else { return }

        let minΔ = deltas.min() ?? 0
        let maxΔ = deltas.max() ?? 0
        let meanΔ = deltas.reduce(0, +) / Double(deltas.count)

        Log.info(
            .camera,
            String(
                format:
                "FPS_WINDOW n=%d mean=%.5f min=%.5f max=%.5f",
                deltas.count,
                meanΔ,
                minΔ,
                maxΔ
            )
        )

        deltas.removeAll(keepingCapacity: true)
        windowCount += 1
    }

    func reset() {
        frameCount = 0
        windowCount = 0
        deltas.removeAll()
    }
}
