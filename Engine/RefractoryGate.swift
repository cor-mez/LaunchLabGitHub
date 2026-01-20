//
//  RefractoryGate.swift
//  LaunchLab
//
//  Refractory Observability (V1)
//
//  ROLE (STRICT):
//  - Observe temporal spacing between impulse-like events
//  - NEVER block, gate, or suppress impulses
//  - NEVER return Bool permission
//  - Authority decides how to interpret timing
//

import Foundation

/// Observational refractory evidence.
/// Carries timing facts only.
struct RefractoryObservation {

    /// Time since previous impulse (seconds)
    let deltaTimeSec: Double
}

/// Stateless temporal observer.
/// Only remembers the immediately previous timestamp.
final class RefractoryGate {

    private var lastImpulseTime: Double?

    func reset(reason: String) {
        lastImpulseTime = nil
        Log.info(.shot, "[OBSERVE] refractory_reset reason=\(reason)")
    }

    /// Observe timing between impulse-like events.
    /// Returns evidence when a previous timestamp exists.
    func observeImpulse(timestamp: Double) -> RefractoryObservation? {

        defer { lastImpulseTime = timestamp }

        guard let last = lastImpulseTime else {
            return nil
        }

        let dt = timestamp - last

        Log.info(
            .shot,
            String(format: "[OBSERVE] refractory_dt=%.4f", dt)
        )

        return RefractoryObservation(
            deltaTimeSec: dt
        )
    }
}
