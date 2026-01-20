//
//  ShotAuthorityGate.swift
//  LaunchLab
//
//  Shot Eligibility Observability (V1)
//
//  ROLE (STRICT):
//  - Observe whether preconditions for a shot MAY exist
//  - Produce evidence only
//  - NEVER gate, arm, authorize, or finalize
//  - All lifecycle decisions live in ShotLifecycleController
//

import Foundation

/// Observational eligibility evidence.
/// Carries facts only — no decisions.
struct ShotEligibilityEvidence {

    let presenceConfidence: Float
    let instantaneousPxPerSec: Double
    let motionPhase: MotionDensityPhase
    let framesSinceIdle: Int
}

/// Stateless eligibility observer.
/// All temporal logic must live in the authority spine.
final class ShotAuthorityGate {

    func reset() {
        // No internal state to reset
    }

    /// Observe eligibility-related facts for this frame.
    func observe(
        presenceConfidence: Float,
        instantaneousPxPerSec: Double,
        motionPhase: MotionDensityPhase,
        framesSinceIdle: Int
    ) -> ShotEligibilityEvidence {

        ShotEligibilityEvidence(
            presenceConfidence: presenceConfidence,
            instantaneousPxPerSec: instantaneousPxPerSec,
            motionPhase: motionPhase,
            framesSinceIdle: framesSinceIdle
        )
    }
}
