//
//  RSGatedPointFilter.swift
//  LaunchLab
//
//  Lightweight geometric filter for RS harness.
//  Overload added for CGPoint-only pipelines.
//

import CoreGraphics

final class RSGatedPointFilter {

    // Existing APIs remain untouched
    // --------------------------------

    // NEW: CGPoint-only overload for measurement harness
    func filter(points: [CGPoint]) -> [CGPoint] {
        guard points.count > 8 else { return points }

        // Simple geometric sanity gate:
        // remove extreme outliers by bounding box percentile
        let xs = points.map { $0.x }.sorted()
        let ys = points.map { $0.y }.sorted()

        let lo = Int(Double(points.count) * 0.05)
        let hi = Int(Double(points.count) * 0.95)

        let minX = xs[lo]
        let maxX = xs[hi]
        let minY = ys[lo]
        let maxY = ys[hi]

        return points.filter {
            $0.x >= minX && $0.x <= maxX &&
            $0.y >= minY && $0.y <= maxY
        }
    }
}
