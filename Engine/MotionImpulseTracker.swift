//
//  MotionImpulseTracker.swift
//  LaunchLab
//
//  Computes motion impulse from recent instantaneous velocity samples.
//  Observation-only. No thresholds. No decisions.
//

import Foundation

struct MotionImpulseSample {
    let instantaneousPxPerSec: Double
    let medianPxPerSec: Double
    let impulseRatio: Double
}

final class MotionImpulseTracker {

    private let windowSize: Int
    private let epsilon: Double

    private var recentPxPerSec: [Double] = []

    init(windowSize: Int = 10, epsilon: Double = 1e-3) {
        self.windowSize = max(3, windowSize)
        self.epsilon = epsilon
    }

    func reset() {
        recentPxPerSec.removeAll()
    }

    func ingest(instantaneousPxPerSec: Double) -> MotionImpulseSample {
        recentPxPerSec.append(instantaneousPxPerSec)

        if recentPxPerSec.count > windowSize {
            recentPxPerSec.removeFirst()
        }

        let median = Self.median(of: recentPxPerSec)
        let impulse = instantaneousPxPerSec / max(median, epsilon)

        return MotionImpulseSample(
            instantaneousPxPerSec: instantaneousPxPerSec,
            medianPxPerSec: median,
            impulseRatio: impulse
        )
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        } else {
            return sorted[mid]
        }
    }
}
