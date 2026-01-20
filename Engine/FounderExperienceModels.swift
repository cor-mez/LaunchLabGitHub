//
//  FounderExperienceModels.swift
//  LaunchLab
//
//  FOUNDER OBSERVABILITY MODELS (V1)
//
//  ROLE (STRICT):
//  - Support founder UI with NON-AUTHORITATIVE diagnostics
//  - Track stability trends and confidence hints
//  - NEVER participate in shot detection, acceptance, or refusal
//

import Foundation
import CoreGraphics

// MARK: - Founder Session Snapshot (OBSERVATIONAL ONLY)

struct FounderSessionSnapshot {
    let timestamp: Date
    let stabilityIndex: Int
    let confidence: Float
    let center: CGPoint?
    let notes: [String]
}

// MARK: - Minimal Founder Frame Input (OBSERVATIONAL)

/// Minimal per-frame input for founder diagnostics.
/// This intentionally avoids rich telemetry to prevent shadow authority.
struct FounderFrameObservation {
    let timestampSec: Double
    let ballLocked: Bool
    let confidence: Float
    let center: CGPoint?
    let estimatedSpeedPxPerSec: Double?
}

// MARK: - Stability Index Calculator (NON-AUTHORITATIVE)

final class ShotStabilityIndexCalculator {

    private var speeds: [Double] = []
    private var confidences: [Float] = []
    private let window: Int

    init(window: Int = 10) {
        self.window = window
    }

    func push(
        speed: Double?,
        confidence: Float
    ) -> Int {

        if let s = speed { speeds.append(s) }
        confidences.append(confidence)

        trim()
        return compute()
    }

    private func trim() {
        if speeds.count > window {
            speeds.removeFirst(speeds.count - window)
        }
        if confidences.count > window {
            confidences.removeFirst(confidences.count - window)
        }
    }

    private func score(from values: [Double]) -> Double {
        guard values.count >= 2 else { return 1.0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean != 0 else { return 1.0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let stdDev = sqrt(variance)
        let normalized = min(stdDev / abs(mean), 1.0)
        return max(0, 1.0 - normalized)
    }

    private func confidenceScore() -> Double {
        guard !confidences.isEmpty else { return 1.0 }
        let mean = confidences.reduce(0, +) / Float(confidences.count)
        return max(0, min(Double(mean) / 20.0, 1.0))
    }

    private func compute() -> Int {
        let speedScore = score(from: speeds)
        let confScore = confidenceScore()
        let composite = (speedScore + confScore) / 2.0
        return Int((composite * 100).rounded())
    }
}

// MARK: - Founder Session Manager (OBSERVATIONAL ONLY)

final class FounderSessionManager {

    private let ssi = ShotStabilityIndexCalculator()

    private(set) var latestSnapshot: FounderSessionSnapshot?
    private(set) var history: [FounderSessionSnapshot] = []

    func reset() {
        history.removeAll()
        latestSnapshot = nil
    }

    /// Process a frame of founder observation.
    /// This method NEVER detects or finalizes shots.
    func handleFrame(_ observation: FounderFrameObservation) {

        let stability = ssi.push(
            speed: observation.estimatedSpeedPxPerSec,
            confidence: observation.confidence
        )

        var notes: [String] = []

        if !observation.ballLocked {
            notes.append("ball_not_locked")
        }

        if observation.estimatedSpeedPxPerSec == nil {
            notes.append("speed_unavailable")
        }

        let snapshot = FounderSessionSnapshot(
            timestamp: Date(),
            stabilityIndex: stability,
            confidence: observation.confidence,
            center: observation.center,
            notes: notes
        )

        latestSnapshot = snapshot
        history.append(snapshot)

        if history.count > 30 {
            history.removeFirst(history.count - 30)
        }
    }
}
