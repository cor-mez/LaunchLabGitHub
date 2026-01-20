//
//  PresenceContinuityLatch.swift
//  LaunchLab
//
//  Presence Continuity Observability (V1)
//
//  ROLE (STRICT):
//  - Compute evidence about recent presence continuity
//  - NEVER latch, confirm, or own time
//  - NEVER emit phase or authority semantics
//

import Foundation

/// Observational continuity evidence.
/// Carries facts only.
struct PresenceContinuityObservation {

    let presenceFrames: Int
    let eligibleToBridge: Bool
}

/// Stateless continuity observer.
/// Caller owns all timing and lifecycle decisions.
final class PresenceContinuityLatch {

    // MARK: - Configuration (OBSERVATIONAL)

    /// Frames of confirmed presence required to consider continuity viable
    private let minPresenceFrames: Int = 4

    // MARK: - State (OBSERVATIONAL ONLY)

    private var presenceFrames: Int = 0

    // MARK: - Reset

    func reset() {
        presenceFrames = 0
    }

    // MARK: - Update

    /// Observe presence this frame and return continuity evidence.
    /// No state is retained beyond simple counting.
    func observe(present: Bool) -> PresenceContinuityObservation {

        if present {
            presenceFrames += 1
        } else {
            presenceFrames = 0
        }

        let eligible = presenceFrames >= minPresenceFrames

        if eligible {
            Log.info(
                .shot,
                "[OBSERVE] presence_continuity frames=\(presenceFrames)"
            )
        }

        return PresenceContinuityObservation(
            presenceFrames: presenceFrames,
            eligibleToBridge: eligible
        )
    }
}
