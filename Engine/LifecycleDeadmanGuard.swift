//
//  LifecycleDeadmanGuard.swift
//  LaunchLab
//
//  Mechanical safety guard (V1)
//
//  ROLE (STRICT):
//  - Observe how long the authority spine remains non-idle
//  - Force refusal if a shot lifecycle stalls
//  - NO knowledge of specific lifecycle phases
//  - NO impact semantics
//

import Foundation

enum DeadmanOutcome {
    case none
    case forceRefuse(reason: RefusalReason)
}

final class LifecycleDeadmanGuard {

    // ---------------------------------------------------------------------
    // MARK: - Configuration (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    /// Absolute max time any non-idle lifecycle may exist (seconds)
    private let maxLifecycleDuration: TimeInterval = 1.0

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    private var lifecycleStartTime: TimeInterval?

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        lifecycleStartTime = nil
    }

    // ---------------------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------------------

    /// Call once per frame.
    /// Returns a forced refusal if the lifecycle stalls.
    func update(
        lifecycleState: ShotLifecycleState,
        timestamp: TimeInterval
    ) -> DeadmanOutcome {

        // Idle clears guard completely
        if lifecycleState == .idle {
            reset()
            return .none
        }

        // First entry into non-idle lifecycle
        if lifecycleStartTime == nil {
            lifecycleStartTime = timestamp
            Log.info(.shot, "deadman_armed t=\(fmt(timestamp))")
            return .none
        }

        // Absolute lifecycle timeout
        let elapsed = timestamp - lifecycleStartTime!
        if elapsed > maxLifecycleDuration {
            Log.info(
                .shot,
                "deadman_force_refuse reason=lifecycle_timeout elapsed=\(fmt(elapsed))"
            )
            return .forceRefuse(reason: .insufficientConfidence)
        }

        return .none
    }

    // ---------------------------------------------------------------------
    // MARK: - Formatting
    // ---------------------------------------------------------------------

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
