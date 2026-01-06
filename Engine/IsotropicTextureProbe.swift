//
//  IsotropicTextureProbe.swift
//  LaunchLab
//
//  CPU-only isotropic texture probe.
//  OBSERVATIONAL ONLY — no authority, no gating.
//
//  Measures directional entropy of feature distribution.
//  High entropy ⇒ isotropic texture (ball-like)
//  Low entropy ⇒ structured texture (edges, text, keyboards)
//

import CoreGraphics
import Foundation

struct IsotropicTextureResult {
    let entropy: Double
    let binCount: Int
}

final class IsotropicTextureProbe {

    // ---------------------------------------------
    // Tunables (conservative, observational)
    // ---------------------------------------------

    private let binCount: Int = 12          // 30° bins
    private let minPoints: Int = 20          // below this entropy is meaningless
    private let epsilon: Double = 1e-6

    // ---------------------------------------------
    // Public API
    // ---------------------------------------------

    /// Computes angular entropy of points relative to centroid.
    /// - Parameter points: feature points in ROI space
    func evaluate(points: [CGPoint]) -> IsotropicTextureResult? {

        guard points.count >= minPoints else { return nil }

        // 1. Compute centroid
        let centroid = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }

        let cx = centroid.x / CGFloat(points.count)
        let cy = centroid.y / CGFloat(points.count)

        // 2. Build angular histogram
        var bins = Array(repeating: 0.0, count: binCount)

        for p in points {
            let dx = Double(p.x - cx)
            let dy = Double(p.y - cy)

            let mag = hypot(dx, dy)
            if mag < epsilon { continue }

            var angle = atan2(dy, dx) // [-π, π]
            if angle < 0 { angle += 2 * .pi }

            let bin = Int(
                floor(angle / (2 * .pi) * Double(binCount))
            ) % binCount

            bins[bin] += 1.0
        }

        // 3. Normalize
        let total = bins.reduce(0, +)
        guard total > 0 else { return nil }

        let probs = bins.map { $0 / total }

        // 4. Shannon entropy
        var entropy: Double = 0

        for p in probs where p > 0 {
            entropy -= p * log2(p)
        }

        return IsotropicTextureResult(
            entropy: entropy,
            binCount: binCount
        )
    }
}
