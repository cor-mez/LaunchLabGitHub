//
//  ImpactImpulseAuthority.swift
//  LaunchLab
//
//  Impact Impulse OBSERVER (V1)
//
//  ROLE (STRICT):
//  - Observe short-lived impulse-like changes in motion.
//  - NEVER authorize, accept, or finalize a shot.
//  - Emit observational signals only.
//  - Safe to run every frame.
//  - All authority lives in ShotLifecycleController.
//

import Foundation

// MARK: - Observation Output (NON-AUTHORITATIVE)

struct ImpactImpulseObservation: Equatable {
    let detected: Bool
    let deltaSpeedPxPerSec: Double
    let framesRemaining: Int
}

// MARK: - Observer

final class ImpactImpulseAuthority {

    // -----------------------------------------------------------
    // Tunables (conservative, observational)
    // -----------------------------------------------------------

    private let minDeltaSpeedPxPerSec: Double = 900.0
    private let maxImpulseFrames: Int = 2

    // -----------------------------------------------------------
    // State (ephemeral)
    // -----------------------------------------------------------

    private var lastSpeed: Double?
    private var framesRemaining: Int = 0
    private var hasEmittedInWindow: Bool = false

    // -----------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------

    func reset() {
        lastSpeed = nil
        framesRemaining = 0
        hasEmittedInWindow = false
    }

    /// Arms a short observational window.
    /// Does NOT imply eligibility or authority.
    func armObservationWindow() {
        framesRemaining = maxImpulseFrames
        hasEmittedInWindow = false
    }

    /// Observes impulse-like behavior.
    /// Returns an observation struct — never a decision.
    func update(speedPxPerSec: Double) -> ImpactImpulseObservation {

        defer { lastSpeed = speedPxPerSec }

        guard framesRemaining > 0,
              let prev = lastSpeed
        else {
            framesRemaining = max(framesRemaining - 1, 0)
            return ImpactImpulseObservation(
                detected: false,
                deltaSpeedPxPerSec: 0,
                framesRemaining: framesRemaining
            )
        }

        let delta = speedPxPerSec - prev
        framesRemaining -= 1

        if !hasEmittedInWindow && delta >= minDeltaSpeedPxPerSec {
            hasEmittedInWindow = true

            Log.info(
                .authority,
                "impulse_observed delta_px_s=\(fmt(delta)) window_remaining=\(framesRemaining)"
            )

            return ImpactImpulseObservation(
                detected: true,
                deltaSpeedPxPerSec: delta,
                framesRemaining: framesRemaining
            )
        }

        return ImpactImpulseObservation(
            detected: false,
            deltaSpeedPxPerSec: delta,
            framesRemaining: framesRemaining
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}
