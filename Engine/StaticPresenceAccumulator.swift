//
//  StaticPresenceAccumulator.swift
//  LaunchLab
//
//  Observes low-motion, static presence using local Y-channel variance.
//  Intended to detect a real ball resting on noisy texture (e.g. turf).
//
//  Observational only. No authority.
//

import Foundation
import CoreGraphics
import CoreVideo

enum StaticPresenceDecision: Equatable {
    case stable(jitter: Double, frames: Int)
    case unstable
    case absent
}

final class StaticPresenceAccumulator {

    // MARK: - Tunables (LOGGING ONLY)

    /// Motion must be below this to consider static presence.
    private let maxSpeedPxPerSec: Double = 8.0

    /// Variance threshold distinguishing ball surface vs turf.
    private let maxVariance: Double = 2.5

    /// Frames required with stable variance.
    private let minStableFrames: Int = 8

    // MARK: - State

    private var recentVariances: [Double] = []
    private var stableCount: Int = 0

    func reset() {
        recentVariances.removeAll()
        stableCount = 0
    }

    /// Observe static presence using Y-channel variance.
    ///
    /// NOTE:
    /// This function assumes variance is already computed upstream
    /// or injected via a helper (kept simple for now).
    func observe(
        center: CGPoint?,
        speedPxPerSec: Double,
        presenceConfidence: Float
    ) -> StaticPresenceDecision {

        guard speedPxPerSec <= maxSpeedPxPerSec else {
            reset()
            return .absent
        }

        guard let variance = sampleLocalVariance() else {
            reset()
            return .absent
        }

        recentVariances.append(variance)
        if recentVariances.count > minStableFrames {
            recentVariances.removeFirst()
        }

        let maxVar = recentVariances.max() ?? variance

        if maxVar <= maxVariance {
            stableCount += 1

            if stableCount >= minStableFrames {
                return .stable(
                    jitter: maxVar,
                    frames: stableCount
                )
            }

            return .unstable
        } else {
            stableCount = 0
            return .unstable
        }
    }

    // MARK: - Placeholder (Explicit)

    /// Placeholder variance sampler.
    ///
    /// IMPORTANT:
    /// This is intentionally simple and returns a synthetic value.
    /// You will replace this with a real Y-sample from the ROI later.
    private func sampleLocalVariance() -> Double? {
        // For now, return a low synthetic variance to validate logic.
        return Double.random(in: 0.6...1.2)
    }
}
