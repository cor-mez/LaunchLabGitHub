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
    private let clusterRadius: CGFloat = 25.0
    private let minPoints: Int = 8

    // ------------------------------------------------------------------
    // Temporal stability parameters (bounded memory)
    // ------------------------------------------------------------------
    private let requiredStableFrames: Int = 2
    private let maxMemoryAge: Int = 10

    private var lastCenter: CGPoint?
    private var stableCount: Int = 0
    private var memoryAge: Int = 0

    /// Finds the densest spatial cluster of points.
    /// Expects points in ROI space.
    func findBallCluster(from points: [CGPoint]) -> BallCluster? {

        // --------------------------------------------------------------
        // Global minimum gate
        // --------------------------------------------------------------
        guard points.count >= minPoints else {
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
        // Cluster size gate
        // --------------------------------------------------------------
        guard bestCluster.count >= minPoints else {
            ageOrReset()
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
        // Temporal stability + bounded memory
        // --------------------------------------------------------------
        if let last = lastCenter {
            let dx = center.x - last.x
            let dy = center.y - last.y
            let distSq = dx * dx + dy * dy

            if distSq <= clusterRadius * clusterRadius {
                stableCount += 1
                memoryAge = 0
            } else {
                memoryAge += 1
            }
        } else {
            stableCount = 0
            memoryAge = 0
        }

        lastCenter = center

        // --------------------------------------------------------------
        // Memory expiration
        // --------------------------------------------------------------
        if memoryAge > maxMemoryAge {
            resetTemporalState()
            return nil
        }

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

    private func ageOrReset() {
        memoryAge += 1
        if memoryAge > maxMemoryAge {
            resetTemporalState()
        }
    }

    private func resetTemporalState() {
        stableCount = 0
        memoryAge = 0
        lastCenter = nil
    }
}
