//
//  ShotAuthorityGate.swift
//  LaunchLab
//
//  Shot Eligibility Gate (V1)
//
//  ROLE (STRICT):
//  - Determine whether conditions are sufficient to BEGIN a shot lifecycle.
//  - NEVER authorize or finalize a shot.
//  - Binary eligibility only.
//  - Safe to call every frame.
//  - All authority lives in ShotLifecycleController.
//

import Foundation

// MARK: - Eligibility Output (NON-AUTHORITATIVE)

enum ShotEligibilityDecision: Equatable {
    case ineligible(reason: String)
    case eligible
}

// MARK: - Lifecycle Context (READ-ONLY)

enum ShotAuthorityLifecycleState: String, Equatable {
    case idle
    case inProgress
}

// MARK: - Config

struct ShotAuthorityGateConfig: Equatable {

    let presenceConfidenceThreshold: Float
    let minMotionPxPerSec: Double
    let requiredMotionFrames: Int
    let minIdleFramesToArm: Int
    let cooldownSec: Double

    init(
        presenceConfidenceThreshold: Float = 80.0,
        minMotionPxPerSec: Double = 220.0,
        requiredMotionFrames: Int = 2,
        minIdleFramesToArm: Int = 12,
        cooldownSec: Double = 0.75
    ) {
        self.presenceConfidenceThreshold = presenceConfidenceThreshold
        self.minMotionPxPerSec = max(0, minMotionPxPerSec)
        self.requiredMotionFrames = max(1, requiredMotionFrames)
        self.minIdleFramesToArm = max(0, minIdleFramesToArm)
        self.cooldownSec = max(0, cooldownSec)
    }
}

// MARK: - Input

struct ShotAuthorityGateInput: Equatable {
    let timestampSec: Double
    let ballLockConfidence: Float
    let instantaneousPxPerSec: Double
    let motionPhase: MotionDensityPhase
    let framesSinceIdle: Int
    let lifecycleState: ShotAuthorityLifecycleState
}

// MARK: - Gate (ELIGIBILITY ONLY)

final class ShotAuthorityGate {

    private enum GateState: Equatable {
        case idle(reason: String)
        case armed
    }

    private let config: ShotAuthorityGateConfig

    private var state: GateState = .idle(reason: "boot")
    private var lastEligibilityTimestampSec: Double?
    private var motionFramesAboveThreshold: Int = 0

    init(config: ShotAuthorityGateConfig = ShotAuthorityGateConfig()) {
        self.config = config
    }

    func reset() {
        state = .idle(reason: "reset")
        lastEligibilityTimestampSec = nil
        motionFramesAboveThreshold = 0
    }

    /// Returns eligibility ONLY.
    /// This gate never authorizes or finalizes a shot.
    func update(_ input: ShotAuthorityGateInput) -> ShotEligibilityDecision {

        // -------------------------------------------------------
        // Lifecycle must be idle to consider eligibility
        // -------------------------------------------------------
        guard input.lifecycleState == .idle else {
            disarm(reason: "lifecycle_in_progress", t: input.timestampSec)
            return .ineligible(reason: "lifecycle_in_progress")
        }

        // -------------------------------------------------------
        // Cooldown gate
        // -------------------------------------------------------
        if let last = lastEligibilityTimestampSec,
           (input.timestampSec - last) < config.cooldownSec {
            return .ineligible(reason: "cooldown_active")
        }

        // -------------------------------------------------------
        // Idle arming requirement
        // -------------------------------------------------------
        let idleEnough = input.framesSinceIdle >= config.minIdleFramesToArm

        switch state {
        case .idle:
            if idleEnough {
                arm(t: input.timestampSec, idleFrames: input.framesSinceIdle)
            } else {
                return .ineligible(reason: "insufficient_idle")
            }

        case .armed:
            break
        }

        // -------------------------------------------------------
        // Armed: check eligibility evidence
        // -------------------------------------------------------

        let presenceOK = input.ballLockConfidence >= config.presenceConfidenceThreshold
        let motionOK = input.instantaneousPxPerSec >= config.minMotionPxPerSec
        let motionNonIdle = (input.motionPhase != .idle)

        if presenceOK && motionOK && motionNonIdle {
            motionFramesAboveThreshold += 1

            if motionFramesAboveThreshold >= config.requiredMotionFrames {

                lastEligibilityTimestampSec = input.timestampSec
                motionFramesAboveThreshold = 0

                Log.info(
                    .authority,
                    "eligible_for_shot t=\(fmt(input.timestampSec)) conf=\(fmt(input.ballLockConfidence)) px_s=\(fmt(input.instantaneousPxPerSec))"
                )

                disarm(reason: "eligibility_emitted", t: input.timestampSec)
                return .eligible
            }

            return .ineligible(reason: "awaiting_persistence")
        }

        // Reset persistence if motion falls away
        motionFramesAboveThreshold = 0
        return .ineligible(reason: "conditions_not_met")
    }

    // MARK: - Transitions

    private func arm(t: Double, idleFrames: Int) {
        state = .armed
        motionFramesAboveThreshold = 0

        Log.info(
            .authority,
            "eligibility_armed t=\(fmt(t)) idleFrames=\(idleFrames)"
        )
    }

    private func disarm(reason: String, t: Double) {
        state = .idle(reason: reason)
        motionFramesAboveThreshold = 0

        Log.info(
            .authority,
            "eligibility_disarmed t=\(fmt(t)) reason=\(reason)"
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
