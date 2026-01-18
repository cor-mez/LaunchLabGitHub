//
//  LifecycleDeadmanGuard.swift
//  LaunchLab
//
//  Mechanical safety guard:
//  Guarantees that once a lifecycle leaves `.idle`,
//  it MUST reach a terminal outcome within a fixed time.
//

import Foundation

enum DeadmanOutcome {
    case none
    case forceRefuse(reason: RefusalReason)
    case forceReset(reason: RefusalReason)
}

final class LifecycleDeadmanGuard {

    // ---------------------------------------------------------------------
    // MARK: - Configuration (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    /// Absolute max time any non-idle lifecycle may exist
    private let maxLifecycleDuration: TimeInterval = 0.500   // 500 ms

    /// Shorter leash once impact has been observed
    private let maxPostImpactDuration: TimeInterval = 0.200  // 200 ms

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    private var lifecycleStartTime: TimeInterval?
    private var impactTime: TimeInterval?

    // ---------------------------------------------------------------------
    // MARK: - Reset
    // ---------------------------------------------------------------------

    func reset() {
        lifecycleStartTime = nil
        impactTime = nil
    }

    // ---------------------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------------------

    /// Call once per frame.
    /// Returns a forced outcome if invariants are violated.
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
        }

        // Track first impact observation
        if lifecycleState == .impactObserved, impactTime == nil {
            impactTime = timestamp
            Log.info(.shot, "deadman_postimpact_armed t=\(fmt(timestamp))")
        }

        // Absolute lifecycle timeout
        if let start = lifecycleStartTime {
            let elapsed = timestamp - start
            if elapsed > maxLifecycleDuration {
                Log.info(
                    .shot,
                    "deadman_force_refuse reason=lifecycle_timeout elapsed=\(fmt(elapsed))"
                )
                return .forceRefuse(reason: .insufficientConfidence)
            }
        }

        // Post-impact timeout (separation skipped, occlusion, ROI exit)
        if let impact = impactTime {
            let elapsed = timestamp - impact
            if elapsed > maxPostImpactDuration {
                Log.info(
                    .shot,
                    "deadman_force_refuse reason=postimpact_timeout elapsed=\(fmt(elapsed))"
                )
                return .forceRefuse(reason: .insufficientConfidence)
            }
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
