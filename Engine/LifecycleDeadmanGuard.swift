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

        // Idle state clears the guard
        if lifecycleState == .idle {
            reset()
            return .none
        }

        // First entry into non-idle lifecycle
        if lifecycleStartTime == nil {
            lifecycleStartTime = timestamp
        }

        // Track first impact observation
        if lifecycleState == .impactObserved, impactTime == nil {
            impactTime = timestamp
        }

        // Absolute lifecycle timeout
        if let start = lifecycleStartTime {
            if timestamp - start > maxLifecycleDuration {
                return .forceRefuse(reason: .lifecycleTimeout)
            }
        }

        // Post-impact timeout (separation skipped, occlusion, ROI exit)
        if let impact = impactTime {
            if timestamp - impact > maxPostImpactDuration {
                return .forceRefuse(reason: .postImpactTimeout)
            }
        }

        return .none
    }
}
