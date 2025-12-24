//
//  BallLockV0.swift
//

import Foundation
import CoreGraphics

struct BallCluster {
    let center: CGPoint
    let radius: CGFloat
    let count: Int
}

final class BallLockV0 {

    // ------------------------------------------------------------------
    // Spatial parameters (tuned)
    // ------------------------------------------------------------------
    private let clusterRadius: CGFloat = 40.0
    private let minPoints: Int = 4

    // ------------------------------------------------------------------
    // Temporal stability parameters (bounded memory)
    // ------------------------------------------------------------------
    private let requiredStableFrames: Int = 3
    private let maxMemoryAge: Int = 10

    private var lastCenter: CGPoint?
    private var stableCount: Int = 0
    private var memoryAge: Int = 0

    /// Binary lock invariant — the ONLY thing downstream should trust
    var isLocked: Bool {
        return stableCount >= requiredStableFrames && memoryAge == 0
    }

    /// Finds the densest spatial cluster of points.
    /// Expects points in ROI space.
    func findBallCluster(from points: [CGPoint]) -> BallCluster? {

        // --------------------------------------------------------------
        // Global minimum gate (absence = reset)
        // --------------------------------------------------------------
        // --------------------------------------------------------------
        // Global minimum gate
        // --------------------------------------------------------------
        guard points.count >= minPoints else {
            if DebugProbe.isEnabled(.capture) {
                Log.info(.ballLock, "rejected points=\(points.count)")
            }
            resetTemporalState()
            return nil
        }

        var bestCluster: [CGPoint] = []

        // --------------------------------------------------------------
        // Brute-force spatial clustering (bounded input)
        // --------------------------------------------------------------
        for p in points {
            var cluster: [CGPoint] = []

            for q in points {
                let dx = p.x - q.x
                let dy = p.y - q.y
                if (dx * dx + dy * dy) <= clusterRadius * clusterRadius {
                    cluster.append(q)
                }
            }

            if cluster.count > bestCluster.count {
                bestCluster = cluster
            }
        }

        // --------------------------------------------------------------
        // Cluster size gate (absence = reset)
        // --------------------------------------------------------------
        guard bestCluster.count >= minPoints else {
            resetTemporalState()
            return nil
        }

        // --------------------------------------------------------------
        // Compute centroid
        // --------------------------------------------------------------
        let sum = bestCluster.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }

        let center = CGPoint(
            x: sum.x / CGFloat(bestCluster.count),
            y: sum.y / CGFloat(bestCluster.count)
        )

        // --------------------------------------------------------------
        // Temporal stability (no grace on disappearance)
        // --------------------------------------------------------------
        if let last = lastCenter {
            let dx = center.x - last.x
            let dy = center.y - last.y
            let distSq = dx * dx + dy * dy

            if distSq <= (clusterRadius * clusterRadius * 1.5) {
                stableCount += 1
                memoryAge = 0
            } else {
                resetTemporalState()
                return nil
            }
        } else {
            stableCount = 0
            memoryAge = 0
        }

        lastCenter = center

        // --------------------------------------------------------------
        // Stable acceptance
        // --------------------------------------------------------------
        guard stableCount >= requiredStableFrames else {
            return nil
        }

        return BallCluster(
            center: center,
            radius: clusterRadius,
            count: bestCluster.count
        )
    }

    // MARK: - Helpers

    private func resetTemporalState() {
        stableCount = 0
        memoryAge = 0
        lastCenter = nil
    }
}
