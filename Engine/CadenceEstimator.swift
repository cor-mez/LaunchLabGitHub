//
//  CadenceEstimator.swift
//  LaunchLab
//
//  Frame Cadence OBSERVER (V1)
//
//  ROLE (STRICT):
//  - Estimate effective frame cadence from timestamps
//  - Provide observational FPS estimate only
//  - NEVER infer validity or authority
//  - Used by authority spine for refusal decisions
//

import Foundation

final class CadenceEstimator {

    // -----------------------------------------------------------
    // MARK: - Tunables (CONSERVATIVE)
    // -----------------------------------------------------------

    /// Number of frame deltas required before reporting FPS
    private let minSamples: Int = 6

    /// Max samples retained for rolling average
    private let maxSamples: Int = 12

    // -----------------------------------------------------------
    // MARK: - State
    // -----------------------------------------------------------

    private var lastTimestamp: Double?
    private var deltas: [Double] = []

    // -----------------------------------------------------------
    // MARK: - Public Observability
    // -----------------------------------------------------------

    /// Estimated frames per second.
    /// Returns 0 until enough samples are collected.
    var estimatedFPS: Double {
        guard deltas.count >= minSamples else { return 0 }
        let avg = deltas.reduce(0, +) / Double(deltas.count)
        return avg > 0 ? (1.0 / avg) : 0
    }

    /// True if cadence is observable (not valid, just measurable)
    var hasEstimate: Bool {
        deltas.count >= minSamples
    }

    // -----------------------------------------------------------
    // MARK: - Lifecycle
    // -----------------------------------------------------------

    func reset() {
        lastTimestamp = nil
        deltas.removeAll()
    }

    /// Push a new frame timestamp (seconds).
    /// Safe to call every frame.
    func push(timestamp: Double) {

        defer { lastTimestamp = timestamp }

        guard let last = lastTimestamp else {
            return
        }

        let dt = timestamp - last
        guard dt > 0 else { return }

        deltas.append(dt)
        if deltas.count > maxSamples {
            deltas.removeFirst()
        }
    }
}
