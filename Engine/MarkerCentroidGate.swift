//
//  MarkerCentroidGate.swift
//  LaunchLab
//
//  Gates marker detections based on short-window centroid motion
//

import CoreGraphics

final class MarkerCentroidGate {

    // -------------------------------------------------------------
    // Tunables (LOCKED FOR V1)
    // -------------------------------------------------------------

    private let windowSize: Int = 5
    private let minDeltaPx: CGFloat = 0.4
    private let maxDeltaPx: CGFloat = 20.0

    // -------------------------------------------------------------
    // State
    // -------------------------------------------------------------

    private var centroids: [CGPoint] = []

    // -------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------

    func reset() {
        centroids.removeAll()
    }

    // -------------------------------------------------------------
    // Gate evaluation
    // -------------------------------------------------------------

    func accept(_ center: CGPoint) -> Bool {

        centroids.append(center)

        if centroids.count > windowSize {
            centroids.removeFirst()
        }

        // Need at least 2 points to measure motion
        guard centroids.count >= 2 else {
            return false
        }

        var deltas: [CGFloat] = []

        for i in 1..<centroids.count {
            let a = centroids[i - 1]
            let b = centroids[i]
            let dx = b.x - a.x
            let dy = b.y - a.y
            deltas.append(sqrt(dx * dx + dy * dy))
        }

        let meanDelta =
            deltas.reduce(0, +) / CGFloat(deltas.count)

        return meanDelta >= minDeltaPx && meanDelta <= maxDeltaPx
    }
}
