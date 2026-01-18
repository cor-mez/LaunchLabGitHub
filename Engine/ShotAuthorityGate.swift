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
    let clusterCompactness: Double?
    let instantaneousPxPerSec: Double
    let motionPhase: MotionDensityPhase
    let framesSinceIdle: Int
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
    private var lastAuthorizedTimestampSec: Double?

    private var motionFramesAboveThreshold: Int = 0
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

        let cooldownElapsed: Bool = {
            guard let last = lastAuthorizedTimestampSec else { return true }
            return (input.timestampSec - last) >= config.cooldownSec
        }()

        let idleEnough = input.framesSinceIdle >= config.minIdleFramesToArm
        let lifecycleIdle = (input.lifecycleState == .idle)

        if !lifecycleIdle {
            disarmIfNeeded(reason: "lifecycle_in_progress", t: input.timestampSec)
            return .notArmed(reason: "lifecycle_in_progress")
        }

        switch state {
        case .notArmed:
            if cooldownElapsed && idleEnough {
                arm(t: input.timestampSec, idleFrames: input.framesSinceIdle)
            }
        case .armed:
            break
        }

        if case .armed = state {

            let presenceOK = input.ballLockConfidence >= config.presenceConfidenceThreshold
            let motionOK = input.instantaneousPxPerSec >= config.minMotionPxPerSec
            let motionNonIdle = (input.motionPhase != .idle)

            if presenceOK && motionOK && motionNonIdle {
                motionFramesAboveThreshold += 1

                if motionFramesAboveThreshold >= config.requiredMotionFrames {
                    lastAuthorizedTimestampSec = input.timestampSec
                    motionFramesAboveThreshold = 0

                    Log.info(
                        .authority,
                        "authorized t=\(fmt(input.timestampSec)) conf=\(fmt(input.ballLockConfidence)) px_s=\(fmt(input.instantaneousPxPerSec))"
                    )

                    disarm(reason: "authorized", t: input.timestampSec)
                    return .authorized
                }

                return .armed
            }

            if motionFramesAboveThreshold > 0 && !motionOK {
                if !blockedLoggedThisCycle {
                    blockedLoggedThisCycle = true
                    Log.info(
                        .authority,
                        "blocked reason=persistence_failed frames=\(motionFramesAboveThreshold)"
                    )
                }
                motionFramesAboveThreshold = 0
            }

            return .armed
        }

        return .notArmed(reason: "not_armed")
    }

    // MARK: - Transitions

    private func arm(t: Double, idleFrames: Int) {
        state = .armed
        blockedLoggedThisCycle = false
        motionFramesAboveThreshold = 0

        Log.info(
            .authority,
            "armed t=\(fmt(t)) idleFrames=\(idleFrames)"
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
            "disarmed t=\(fmt(t)) reason=\(reason)"
        )
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
