//
//  DotTracker.swift
//  LaunchLab
//

import CoreGraphics

final class DotTracker {

    private let gate: CGFloat = 12.0

    func track(prev: [VisionDot], currPoints: [CGPoint]) -> [VisionDot] {

        guard !prev.isEmpty, !currPoints.isEmpty else {
            return currPoints.enumerated().map { (i, p) in
                VisionDot(id: i, position: p)
            }
        }

        var unused = currPoints
        var out: [VisionDot] = []

        for dot in prev {

            // Predicted from KF-enhanced velocity
            let predicted = dot.predicted ?? dot.position

            // Find nearest neighbor
            var bestIdx: Int?
            var bestDist = CGFloat.greatestFiniteMagnitude

            for (i, p) in unused.enumerated() {
                let dx = p.x - predicted.x
                let dy = p.y - predicted.y
                let d = dx*dx + dy*dy
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }

            if let idx = bestIdx, sqrt(bestDist) <= gate {
                let pos = unused.remove(at: idx)
                out.append(
                    VisionDot(
                        id: dot.id,
                        position: pos,
                        predicted: predicted,
                        velocity: dot.velocity
                    )
                )
            }
        }

        // Add new IDs for unmatched points
        let maxID = (prev.map { $0.id }.max() ?? -1)
        for (j, p) in unused.enumerated() {
            out.append(
                VisionDot(
                    id: maxID + 1 + j,
                    position: p,
                    predicted: p,
                    velocity: .zero
                )
            )
        }

        return out
    }
}
