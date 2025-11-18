//
//  RSTimingModel.swift
//  LaunchLab
//

import Foundation
import simd

/// Computes per-dot rolling-shutter timestamps based on line index.
/// This is a placeholder linear model until we run RS calibration.
final class RSTimingModel {

    /// Estimated full-frame readout duration (seconds).
    /// iPhone 16 Pro @ 240 FPS ≈ 1/240 ≈ 4.17 ms exposure window.
    /// Real calibration will replace this number.
    private let readout: Float = 0.0039   // seconds

    public func computeDotTimes(
        frame: VisionFrameData,
        dotPositions: [SIMD2<Float>]
    ) -> [Float] {

        let h = Float(frame.height)
        guard h > 1 else {
            return Array(repeating: Float(frame.timestamp), count: dotPositions.count)
        }

        var ts = [Float]()
        ts.reserveCapacity(dotPositions.count)

        for p in dotPositions {
            let y = max(0, min(h - 1, p.y))
            let rowFrac = y / (h - 1)             // 0 → 1
            let dt = rowFrac * readout            // linear RS model
            ts.append(Float(frame.timestamp) + dt)
        }

        return ts
    }
}