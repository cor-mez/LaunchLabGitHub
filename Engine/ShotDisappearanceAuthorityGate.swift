//
//  ShotDisappearanceAuthorityGate.swift
//  LaunchLab
//
//  Disappearance Observability Module (V1)
//
//  ROLE (STRICT):
//  - Observe post-impact disappearance timing
//  - Produce observational evidence only
//  - NEVER authorize, confirm, or finalize a shot
//

import Foundation

/// Observational disappearance evidence.
/// Carries facts, not decisions.
struct DisappearanceObservation {

    let framesSinceImpact: Int
    let cameraStable: Bool
    let disappeared: Bool
}

/// Observes whether and when the ball disappears after impact.
/// All authority is deferred to ShotLifecycleController.
final class ShotDisappearanceAuthorityGate {

    // MARK: - Parameters (OBSERVATIONAL)

    /// Frames after impact in which disappearance is considered relevant
    private let maxFramesAfterImpact: Int = 4

    /// Require the ball to have been present immediately before impact
    private let requirePreImpactPresence: Bool = true

    // MARK: - State (OBSERVATIONAL ONLY)

    private var armed: Bool = false
    private var framesSinceImpact: Int = 0

    // MARK: - Lifecycle

    func reset() {
        armed = false
        framesSinceImpact = 0
    }

    /// Arm observation window on confirmed impact (observational signal).
    func arm() {
        armed = true
        framesSinceImpact = 0
        Log.info(.shot, "[OBSERVE] disappearance armed")
    }

    /// Advance one frame while armed.
    func advanceFrame() {
        guard armed else { return }
        framesSinceImpact += 1
    }

    /// Observe disappearance characteristics for the current frame.
    /// Returns a DisappearanceObservation when disappearance is observed
    /// or when the observation window expires.
    func observe(
        ballPresent: Bool,
        cameraStable: Bool
    ) -> DisappearanceObservation? {

        guard armed else { return nil }

        // Camera stability is observed, not enforced
        if !cameraStable {
            Log.info(.shot, "[OBSERVE] disappearance camera_unstable")
            reset()
            return DisappearanceObservation(
                framesSinceImpact: framesSinceImpact,
                cameraStable: false,
                disappeared: false
            )
        }

        // Ball disappears within window
        if !ballPresent {
            Log.info(
                .shot,
                "[OBSERVE] disappearance detected frames=\(framesSinceImpact)"
            )
            reset()
            return DisappearanceObservation(
                framesSinceImpact: framesSinceImpact,
                cameraStable: true,
                disappeared: true
            )
        }

        // Observation window expired
        if framesSinceImpact > maxFramesAfterImpact {
            Log.info(
                .shot,
                "[OBSERVE] disappearance window_expired frames=\(framesSinceImpact)"
            )
            reset()
            return DisappearanceObservation(
                framesSinceImpact: framesSinceImpact,
                cameraStable: cameraStable,
                disappeared: false
            )
        }

        return nil
    }
}
