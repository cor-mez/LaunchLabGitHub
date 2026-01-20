//
//  RefractoryGate.swift
//  LaunchLab
//
//  Prevents repeated authority claims from temporally adjacent impulses.
//  This is NOT a detector — it is a safety gate.
//

import Foundation

final class RefractoryGate {

    // -------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------

    private(set) var isLocked: Bool = false
    private var lastImpulseTime: Double? = nil

    // -------------------------------------------------------------
    // MARK: - Tunables (LOCKED FOR DIAGNOSIS)
    // -------------------------------------------------------------

    /// Minimum time between accepted impulses (seconds)
    private let refractoryDuration: Double = 0.020  // 20 ms

    // -------------------------------------------------------------
    // MARK: - Reset
    // -------------------------------------------------------------

    func reset(reason: String) {
        isLocked = false
        lastImpulseTime = nil
        Log.info(.shot, "REFRACTORY_RESET reason=\(reason)")
    }

    // -------------------------------------------------------------
    // MARK: - Attempt Acceptance
    // -------------------------------------------------------------

    /// Returns true iff the impulse is allowed to proceed
    func tryAcceptImpulse(timestamp: Double) -> Bool {

        if let last = lastImpulseTime {
            let dt = timestamp - last
            if dt < refractoryDuration {
                return false
            }
        }

        // Accept and lock
        lastImpulseTime = timestamp
        isLocked = true

        Log.info(
            .shot,
            String(format: "REFRACTORY_LOCK t=%.3f", timestamp)
        )

        return true
    }

    // -------------------------------------------------------------
    // MARK: - Update / Release
    // -------------------------------------------------------------

    /// Called every frame so release is explicit and observable
    func update(timestamp: Double, sceneIsQuiet: Bool) {

        guard isLocked else { return }

        guard let last = lastImpulseTime else { return }

        let dt = timestamp - last

        // Only release once:
        // 1) enough time has passed
        // 2) scene is no longer impulsive
        if dt >= refractoryDuration && sceneIsQuiet {
            isLocked = false
            Log.info(
                .shot,
                String(format: "REFRACTORY_RELEASE t=%.3f", timestamp)
            )
        }
    }
}
