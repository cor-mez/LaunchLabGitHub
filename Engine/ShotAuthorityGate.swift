//
//  ShotAuthorityGate.swift
//  LaunchLab
//
//  Shot Authority Gate (V1)
//
//  Role:
//  - Decide if the system is allowed to declare a shot start.
//  - Binary decisions only; no scoring.
//  - Logs transitions only (no per-frame spam).
//

import Foundation

// MARK: - Output

enum ShotAuthorityDecision: Equatable {
    case notArmed(reason: String)
    case armed
    case authorized
}

// MARK: - Lifecycle State Input (context authority)

enum ShotAuthorityLifecycleState: String, Equatable {
    case idle
    case inProgress
}

// MARK: - Config

struct ShotAuthorityGateConfig: Equatable {

    /// Presence authority threshold (BallLock confidence must be >= this).
    let presenceConfidenceThreshold: Float

    /// Motion authority threshold (instantaneous px/s must be >= this).
    let minMotionPxPerSec: Double

    /// Motion persistence required to authorize (>=2 frames).
    let requiredMotionFrames: Int

    /// Context authority: required quiet/idle frames before arming.
    let minIdleFramesToArm: Int

    /// Context authority: cooldown after authorization.
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
    let clusterCompactness: Double?         // optional; pass nil if unavailable
    let instantaneousPxPerSec: Double
    let motionPhase: MotionDensityPhase     // observed, not derived here
    let framesSinceIdle: Int                // MUST come from SceneQuietGate
    let lifecycleState: ShotAuthorityLifecycleState
}

// MARK: - Gate

final class ShotAuthorityGate {

    private enum GateState: Equatable {
        case notArmed(reason: String)
        case armed
    }

    private let config: ShotAuthorityGateConfig

    private var state: GateState = .notArmed(reason: "boot")
    private var lastAuthorizedTimestampSec: Double? = nil

    private var motionFramesAboveThreshold: Int = 0

    // Spam guard: log blocked only once per arm cycle.
    private var blockedLoggedThisCycle: Bool = false

    init(config: ShotAuthorityGateConfig = ShotAuthorityGateConfig()) {
        self.config = config
    }

    func reset() {
        state = .notArmed(reason: "reset")
        lastAuthorizedTimestampSec = nil
        motionFramesAboveThreshold = 0
        blockedLoggedThisCycle = false
    }

    func update(_ input: ShotAuthorityGateInput) -> ShotAuthorityDecision {

        // Context authority checks
        let cooldownElapsed: Bool = {
            guard let last = lastAuthorizedTimestampSec else { return true }
            return (input.timestampSec - last) >= config.cooldownSec
        }()

        let idleEnough = input.framesSinceIdle >= config.minIdleFramesToArm
        let lifecycleIdle = (input.lifecycleState == .idle)

        // If lifecycle is in progress, we cannot arm or authorize.
        if !lifecycleIdle {
            disarmIfNeeded(reason: "lifecycle_in_progress", t: input.timestampSec)
            return .notArmed(reason: "lifecycle_in_progress")
        }

        // Arm if eligible and currently not armed.
        switch state {
        case .notArmed:
            if cooldownElapsed && idleEnough {
                arm(t: input.timestampSec, idleFrames: input.framesSinceIdle)
            }
        case .armed:
            break
        }

        // Authorization check
        if case .armed = state {

            let presenceOK = input.ballLockConfidence >= config.presenceConfidenceThreshold
            let motionOK = input.instantaneousPxPerSec >= config.minMotionPxPerSec
            let motionNonIdle = (input.motionPhase != .idle)

            if presenceOK && motionOK && motionNonIdle {
                motionFramesAboveThreshold += 1

                if motionFramesAboveThreshold >= config.requiredMotionFrames {
                    // Authorize exactly once, then disarm.
                    lastAuthorizedTimestampSec = input.timestampSec
                    motionFramesAboveThreshold = 0

                    Log.info(
                        .authority,
                        "authorized " +
                        "t=\(fmt(input.timestampSec)) " +
                        "conf=\(fmt(input.ballLockConfidence)) " +
                        "px_s=\(fmt(input.instantaneousPxPerSec)) " +
                        "frames=\(config.requiredMotionFrames)"
                    )

                    disarm(reason: "authorized", t: input.timestampSec)
                    return .authorized
                }

                // Still accumulating; no log.
                return .armed
            }

            // If we were accumulating and motion dropped, treat as a blocked attempt (once).
            if motionFramesAboveThreshold > 0 && !motionOK {
                if !blockedLoggedThisCycle {
                    blockedLoggedThisCycle = true
                    Log.info(
                        .authority,
                        "blocked " +
                        "t=\(fmt(input.timestampSec)) " +
                        "reason=persistence_failed " +
                        "frames=\(motionFramesAboveThreshold) " +
                        "conf=\(fmt(input.ballLockConfidence)) " +
                        "px_s=\(fmt(input.instantaneousPxPerSec))"
                    )
                }
                motionFramesAboveThreshold = 0
                return .armed
            }

            // If motion is strong but we're missing presence, log blocked once.
            if motionOK && !presenceOK {
                if !blockedLoggedThisCycle {
                    blockedLoggedThisCycle = true
                    Log.info(
                        .authority,
                        "blocked " +
                        "t=\(fmt(input.timestampSec)) " +
                        "reason=presence_low " +
                        "conf=\(fmt(input.ballLockConfidence)) " +
                        "thr=\(fmt(config.presenceConfidenceThreshold)) " +
                        "px_s=\(fmt(input.instantaneousPxPerSec))"
                    )
                }
                return .armed
            }

            return .armed
        }

        // Not armed: if motion is happening, log blocked once with reason.
        let motionEvent = input.instantaneousPxPerSec >= config.minMotionPxPerSec
        if motionEvent {
            if case .notArmed(let reason) = state {
                if !blockedLoggedThisCycle {
                    blockedLoggedThisCycle = true
                    Log.info(
                        .authority,
                        "blocked " +
                        "t=\(fmt(input.timestampSec)) " +
                        "reason=not_armed:\(reason) " +
                        "idleFrames=\(input.framesSinceIdle) " +
                        "cooldown=\(fmt(timeSinceLastAuthorized(now: input.timestampSec))) " +
                        "conf=\(fmt(input.ballLockConfidence)) " +
                        "px_s=\(fmt(input.instantaneousPxPerSec))"
                    )
                }
            }
        }

        let reason: String = {
            if !cooldownElapsed { return "cooldown" }
            if !idleEnough { return "scene_not_quiet" }
            return "not_armed"
        }()

        state = .notArmed(reason: reason)
        return .notArmed(reason: reason)
    }

    // MARK: - Transitions

    private func arm(t: Double, idleFrames: Int) {
        state = .armed
        blockedLoggedThisCycle = false
        motionFramesAboveThreshold = 0

        Log.info(
            .authority,
            "armed " +
            "t=\(fmt(t)) " +
            "idleFrames=\(idleFrames) " +
            "cooldown=\(fmt(timeSinceLastAuthorized(now: t)))"
        )
    }

    private func disarmIfNeeded(reason: String, t: Double) {
        if case .armed = state {
            disarm(reason: reason, t: t)
        } else {
            state = .notArmed(reason: reason)
        }
    }

    private func disarm(reason: String, t: Double) {
        state = .notArmed(reason: reason)
        motionFramesAboveThreshold = 0
        blockedLoggedThisCycle = false

        Log.info(
            .authority,
            "disarmed " +
            "t=\(fmt(t)) " +
            "reason=\(reason)"
        )
    }

    private func timeSinceLastAuthorized(now: Double) -> Double? {
        guard let last = lastAuthorizedTimestampSec else { return nil }
        return max(0, now - last)
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Double?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.3f", v)
    }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
