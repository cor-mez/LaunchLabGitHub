//
//  SpatialPresenceObserver.swift
//  LaunchLab
//
//  Observes static ball presence via spatial occupancy stability.
//  Does NOT use FAST9.
//  Does NOT gate shots.
//  Observational truth only.
//

import Foundation
import CoreGraphics

enum SpatialPresenceDecision {
    case present(stability: Double, frames: Int)
    case unstable
    case absent
}

final class SpatialPresenceObserver {

    // MARK: - Config (logging-only, conservative)

    private let minConfidence: Float = 120
    private let minStableFrames: Int = 8
    private let minOverlapRatio: Double = 0.85
    private let minPixelCount: Int = 60
    private let maxPixelDriftRatio: Double = 0.15

    // MARK: - State

    private var lastMask: Set<Int>?
    private var stableFrames: Int = 0

    func reset() {
        lastMask = nil
        stableFrames = 0
    }

    /// Observe a binary occupancy mask (ball-like pixels)
    func observe(
        mask: Set<Int>?,
        confidence: Float
    ) -> SpatialPresenceDecision {

        guard confidence >= minConfidence else {
            reset()
            return .absent
        }

        guard let mask, mask.count >= minPixelCount else {
            reset()
            return .absent
        }

        guard let last = lastMask else {
            lastMask = mask
            stableFrames = 1
            return .unstable
        }

        let intersection = last.intersection(mask).count
        let union = last.union(mask).count

        guard union > 0 else {
            reset()
            return .absent
        }

        let overlapRatio = Double(intersection) / Double(union)
        let driftRatio = 1.0 - overlapRatio

        if overlapRatio >= minOverlapRatio && driftRatio <= maxPixelDriftRatio {
            stableFrames += 1
            lastMask = mask

            if stableFrames >= minStableFrames {
                return .present(
                    stability: overlapRatio,
                    frames: stableFrames
                )
            }

            return .unstable
        } else {
            reset()
            return .unstable
        }
    }
}
