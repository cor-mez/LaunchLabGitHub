//
//  ShotAuthorityGate.swift
//  LaunchLab
//
//  Engine-only "bouncer" for shot starts (V1)
//  ------------------------------------------------------------
//  This module decides ONLY whether a motion event is allowed to
//  become a shot. It does not compute metrics, smooth data, or
//  modify BallLock / FAST9 / lifecycle internals.
//
//  Outputs:
//    - notArmed(reason:)
//    - armed
//    - authorized
//
//  Logging (MANDATORY, transition-based; no per-frame spam):
//    [AUTHORITY] armed ...
//    [AUTHORITY] disarmed reason=...
//    [AUTHORITY] authorized ...
//    [AUTHORITY] blocked reason=...
//

import Foundation

// MARK: - Output

enum ShotAuthorityDecision: Equatable {
    case notArmed(reason: String)
    case armed
    case authorized

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }

    var isArmed: Bool {
        if case .armed = self { return true }
        return false
    }
}

// MARK: - Context (input contract)

enum ShotAuthorityLifecycleState: String, Equatable {
    case idle
    case inProgress
    case cooldown
}

// MARK: - Input Snapshot

struct ShotAuthorityInput: Equatable {
    let timestampSec: Double

    // Presence authority
    let ballLockConfidence: Float
    let clusterCompactness: Double?  // pass nil if unavailable

    // Motion authority
    let instantaneousPxPerSec: Double
    let motionPhase: MotionDensityPhase

    // Context authority
    let framesSinceIdle: Int
    let timeSinceLastAuthoritativeShotSec: Double?   // nil if never
    let lifecycleState: ShotAuthorityLifecycleState
}

// MARK: - Config

struct ShotAuthorityConfig: Equatable {

    // Presence must be strong enough to consider motion "real"
    var presenceConfidenceThreshold: Float = 120

    // Motion candidate threshold (instantaneous)
    var minMotionPxPerSec: Double = 400

    // Idle definition (used for arming)
    var idleMotionMaxPxPerSec: Double = 50
    var requiredIdleFramesToArm: Int = 8

    // Authorization persistence requirement
    var requiredMotionFrames: Int = 2

    // Cooldown after authorization (context authority)
    var cooldownSec: Double = 0.50

    // Directional change proxy (approach → impact)
    // This relies on motionPhase being provided by upstream code.
    var requireApproachThenImpact: Bool = true

    init() {}
}

// MARK: - Gate

final class ShotAuthorityGate {

    // Exposed so DotTestCoordinator can use consistent thresholds
    let config: ShotAuthorityConfig

    // Internal state
    private var armed: Bool = false
    private var lastDecision: ShotAuthorityDecision = .notArmed(reason: "boot")

    private var lastAuthorizedTimestampSec: Double? = nil

    // Candidate tracking (motion persistence + direction proxy)
    private var candidateMotionFrames: Int = 0
    private var sawApproachInCandidate: Bool = false

    // Log spam guards
    private var blockedLatchActive: Bool = false
    private var lastBlockedReason: String? = nil
    private var lastDisarmReason: String? = nil

    init(config: ShotAuthorityConfig = ShotAuthorityConfig()) {
        self.config = config
    }

    // MARK: - Update

    func update(_ input: ShotAuthorityInput) -> ShotAuthorityDecision {

        // ------------------------------------------------------------
        // Context authority: lifecycle must be idle to listen/start
        // ------------------------------------------------------------

        if input.lifecycleState != .idle {
            disarmIfNeeded(reason: "lifecycle_not_idle(\(input.lifecycleState.rawValue))", input: input)
            return setDecision(.notArmed(reason: "lifecycle_not_idle"))
        }

        // ------------------------------------------------------------
        // Context authority: cooldown must elapse
        // ------------------------------------------------------------

        if let last = lastAuthorizedTimestampSec {
            let dt = input.timestampSec - last
            if dt < config.cooldownSec {
                disarmIfNeeded(reason: "cooldown(\(fmt(dt))/\(fmt(config.cooldownSec))s)", input: input)
                return setDecision(.notArmed(reason: "cooldown"))
            }
        }

        // ------------------------------------------------------------
        // Arming logic: require stable idle window (motion-decayed scene)
        // IMPORTANT: we do NOT require "no ball" to arm. A ball can be
        // present and stationary; arming is about readiness to listen.
        // ------------------------------------------------------------

        let idleEnough =
            input.framesSinceIdle >= max(1, config.requiredIdleFramesToArm) &&
            input.instantaneousPxPerSec <= config.idleMotionMaxPxPerSec

        if !armed {
            if idleEnough {
                arm(input: input)
                return setDecision(.armed)
            } else {
                // Not armed, waiting for idle window; no per-frame logs.
                return setDecision(.notArmed(reason: "waiting_for_idle"))
            }
        }

        // ------------------------------------------------------------
        // Armed: evaluate motion candidate for authorization
        // ------------------------------------------------------------

        let presenceOk = input.ballLockConfidence >= config.presenceConfidenceThreshold

        let motionCandidate = input.instantaneousPxPerSec >= config.minMotionPxPerSec

        // Reset candidate + unblock latch when motion is not active
        if !motionCandidate {
            resetCandidate()
            unblockLatchIfNeeded()
            return setDecision(.armed)
        }

        // Track approach→impact proxy
        if input.motionPhase == .approach {
            sawApproachInCandidate = true
        }

        // If motion is present but ball presence is weak -> blocked
        guard presenceOk else {
            blockOnce(
                reason: "motion_without_presence",
                input: input
            )
            resetCandidate()
            return setDecision(.armed)
        }

        // Direction proxy: require approach then impact (if enabled)
        if config.requireApproachThenImpact {
            if !sawApproachInCandidate {
                // We are in motion but never saw approach
                blockOnce(
                    reason: "missing_approach_phase",
                    input: input
                )
                resetCandidate()
                return setDecision(.armed)
            }
            if input.motionPhase != .impact {
                // We only authorize on impact phase in this mode
                return setDecision(.armed)
            }
        }

        // Motion persistence (>= 2 frames)
        candidateMotionFrames += 1

        if candidateMotionFrames < max(1, config.requiredMotionFrames) {
            // Not enough persistence yet; no logs.
            return setDecision(.armed)
        }

        // AUTHORIZED: disarm immediately + enter cooldown
        authorize(input: input)
        return setDecision(.authorized)
    }

    // MARK: - Internal transitions

    private func arm(input: ShotAuthorityInput) {
        armed = true
        resetCandidate()
        unblockLatchIfNeeded()

        Log.info(
            .authority,
            "armed " +
            "t=\(fmt(input.timestampSec)) " +
            "idleFrames=\(input.framesSinceIdle) " +
            "v=\(fmt(input.instantaneousPxPerSec))"
        )
    }

    private func authorize(input: ShotAuthorityInput) {
        armed = false
        lastAuthorizedTimestampSec = input.timestampSec

        // Prevent immediate re-triggering by clearing candidate state
        resetCandidate()
        unblockLatchIfNeeded()
        lastDisarmReason = nil

        Log.info(
            .authority,
            "authorized " +
            "t=\(fmt(input.timestampSec)) " +
            "conf=\(fmt(input.ballLockConfidence)) " +
            "v=\(fmt(input.instantaneousPxPerSec)) " +
            "motion=\(input.motionPhase.rawValue)"
        )
    }

    private func disarmIfNeeded(reason: String, input: ShotAuthorityInput) {
        guard armed else { return }
        armed = false
        resetCandidate()
        unblockLatchIfNeeded()

        if lastDisarmReason != reason {
            lastDisarmReason = reason
            Log.info(
                .authority,
                "disarmed " +
                "t=\(fmt(input.timestampSec)) " +
                "reason=\(reason)"
            )
        }
    }

    private func blockOnce(reason: String, input: ShotAuthorityInput) {
        // Only log once per candidate until motion drops below threshold.
        if blockedLatchActive && lastBlockedReason == reason { return }

        blockedLatchActive = true
        lastBlockedReason = reason

        Log.info(
            .authority,
            "blocked " +
            "t=\(fmt(input.timestampSec)) " +
            "reason=\(reason) " +
            "conf=\(fmt(input.ballLockConfidence)) " +
            "v=\(fmt(input.instantaneousPxPerSec)) " +
            "motion=\(input.motionPhase.rawValue) " +
            "idleFrames=\(input.framesSinceIdle)"
        )
    }

    private func unblockLatchIfNeeded() {
        blockedLatchActive = false
        lastBlockedReason = nil
    }

    private func resetCandidate() {
        candidateMotionFrames = 0
        sawApproachInCandidate = false
    }

    // MARK: - Decision tracking

    @discardableResult
    private func setDecision(_ d: ShotAuthorityDecision) -> ShotAuthorityDecision {
        lastDecision = d
        return d
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
