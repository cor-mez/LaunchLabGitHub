//
//  ShotPhaseTracker.swift
//  LaunchLab
//
//  Shot Phase Observability (V1)
//
//  ROLE (STRICT):
//  - Observe phase-like physical signals
//  - NEVER enforce ordering
//  - NEVER confirm or reject
//  - NEVER own lifecycle or time
//

import Foundation
import CoreGraphics

/// Observational phase evidence.
/// Carries facts only.
struct ShotPhaseObservation {

    let impulseTimestamp: Double?
    let impactX: CGFloat?
    let awaitingBallEmergence: Bool
}

/// Stateless helper for packaging phase-related evidence.
/// All authority decisions are deferred to ShotLifecycleController.
final class ShotPhaseTracker {

    private var lastImpulseTimestamp: Double?
    private var lastImpactX: CGFloat?

    func reset() {
        lastImpulseTimestamp = nil
        lastImpactX = nil
    }

    /// Observe an impulse-like event.
    func observeImpulse(
        timestamp: Double,
        impactX: CGFloat
    ) {
        lastImpulseTimestamp = timestamp
        lastImpactX = impactX

        Log.info(
            .shot,
            "[OBSERVE] impulse timestamp=\(fmt(timestamp)) x=\(fmt2(impactX))"
        )
    }

    /// Observe that the system is awaiting ball emergence.
    func observeAwaitingBall() -> ShotPhaseObservation {

        Log.info(.shot, "[OBSERVE] awaiting_ball_emergence")

        return ShotPhaseObservation(
            impulseTimestamp: lastImpulseTimestamp,
            impactX: lastImpactX,
            awaitingBallEmergence: true
        )
    }

    /// Observe current phase evidence without implying progression.
    func snapshot() -> ShotPhaseObservation {

        ShotPhaseObservation(
            impulseTimestamp: lastImpulseTimestamp,
            impactX: lastImpactX,
            awaitingBallEmergence: false
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func fmt2(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
    }
}
