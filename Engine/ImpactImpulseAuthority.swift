//
//  ImpactImpulseAuthority.swift
//  LaunchLab
//
//  Impact Impulse Observability (V1)
//
//  ROLE (STRICT):
//  - Observe instantaneous changes in motion magnitude
//  - Produce derivative evidence only
//  - NEVER latch, arm, window, or emit once
//  - NEVER imply timing or authority
//

import Foundation

/// Instantaneous impulse evidence.
/// Represents a single-frame derivative only.
struct ImpactImpulseObservation {

    let deltaSpeedPxPerSec: Double
}

/// Stateless impulse observer.
/// Caller owns all temporal interpretation.
final class ImpactImpulseAuthority {

    private var lastSpeed: Double?

    func reset() {
        lastSpeed = nil
    }

    /// Observe instantaneous change in speed.
    /// Always returns a value when a previous sample exists.
    func observe(speedPxPerSec: Double) -> ImpactImpulseObservation? {

        defer { lastSpeed = speedPxPerSec }

        guard let prev = lastSpeed else {
            return nil
        }

        let delta = speedPxPerSec - prev

        Log.info(
            .shot,
            "[OBSERVE] impulse_delta_px_s=\(fmt(delta))"
        )

        return ImpactImpulseObservation(
            deltaSpeedPxPerSec: delta
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
