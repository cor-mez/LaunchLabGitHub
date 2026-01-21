//
//  ShotSessionStore.swift
//  LaunchLab
//
//  Engine-level session aggregator (V1)
//  Owns completed shots and emits session activity logs.
//  No UI, no persistence, no heuristics.
//

import Foundation

@MainActor
final class ShotSessionStore {

    // MARK: - Configuration

    /// Emit a session summary log every N completed shots.
    private let summaryLogInterval: Int

    // MARK: - State

    private(set) var shots: [EngineShotSummary] = []

    // MARK: - Init

    init(summaryLogInterval: Int = 5) {
        self.summaryLogInterval = max(1, summaryLogInterval)
    }

    // MARK: - Public API

    func append(_ summary: EngineShotSummary) {
        shots.append(summary)

        logShot(summary)

        if shots.count % summaryLogInterval == 0 {
            logSessionSummary()
        }
    }

    func reset() {
        shots.removeAll()
        Log.info(.shot, "session_reset")
    }

    // MARK: - Logging

    private func logShot(_ s: EngineShotSummary) {

        let id = s.shotId
        let finalState = s.finalState
        let refused = s.refused
        let refusal = s.refusalReason ?? "none"

        let message =
            "shot_recorded " +
            "id=\(id) " +
            "final=\(finalState) " +
            "refused=\(refused) " +
            "reason=\(refusal)"

        Log.info(.shot, message)
    }

    private func logSessionSummary() {

        let total = shots.count
        let refusedCount = shots.filter { $0.refused }.count
        let acceptedCount = total - refusedCount

        let message =
            "session_summary " +
            "shots=\(total) " +
            "accepted=\(acceptedCount) " +
            "refused=\(refusedCount)"

        Log.info(.shot, message)
    }
}
