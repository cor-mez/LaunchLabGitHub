//
//  ShotLifecycleController.swift
//  LaunchLab
//
//  Canonical Shot Authority Spine (V1)
//
//  PROPERTIES:
//  - Single authority
//  - Refusal-first
//  - No discovery logic
//  - Guaranteed termination (deadman timer)
//  - Acceptance intentionally frozen
//

import Foundation

// MARK: - Lifecycle States

enum ShotLifecycleState: String {
    case idle
    case preImpact
    case impactObserved
    case postImpact
    case shotFinalized
    case refused
}

// MARK: - Input Snapshot (AUTHORITY-ONLY)

struct ShotLifecycleInput {

    let timestampSec: Double

    // HARD OBSERVABILITY
    let captureValid: Bool
    let rsObservable: Bool

    // UPSTREAM GATING
    let eligibleForShot: Bool
    let confirmedByUpstream: Bool   // intentionally false in V1

    // CONTEXT (NON-AUTHORITATIVE)
    let ballLockConfidence: Float
    let motionDensityPhase: MotionDensityPhase
    let ballSpeedPxPerSec: Double?

    // EXPLICIT REFUSAL (OVERRIDE)
    let refusalReason: RefusalReason?
}

// MARK: - Record

struct ShotLifecycleRecord {
    let shotId: Int
    let startTimestamp: Double
    let impactTimestamp: Double?
    let endTimestamp: Double
    let refused: Bool
    let refusalReason: RefusalReason?
    let finalState: ShotLifecycleState
}

// MARK: - Controller (SINGULAR AUTHORITY)

final class ShotLifecycleController {

    // -----------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------

    /// Maximum allowed non-idle lifetime before forced reset (seconds)
    private let deadmanTimeoutSec: Double = 1.0

    // -----------------------------------------------------------
    // State
    // -----------------------------------------------------------

    private(set) var state: ShotLifecycleState = .idle
    private var nextShotId: Int = 1

    private var startTimestamp: Double?
    private var impactTimestamp: Double?
    private var lastStateChangeTimestamp: Double?

    // -----------------------------------------------------------
    // Update (ONLY ENTRY POINT)
    // -----------------------------------------------------------

    func update(_ input: ShotLifecycleInput) -> ShotLifecycleRecord? {

        // -------------------------------------------------------
        // DEADMAN TIMEOUT (ABSOLUTE SAFETY)
        // -------------------------------------------------------

        if let lastChange = lastStateChangeTimestamp,
           state != .idle,
           (input.timestampSec - lastChange) > deadmanTimeoutSec {

            Log.info(
                .shot,
                "shot_deadman_timeout t=\(fmt(input.timestampSec)) state=\(state.rawValue)"
            )

            return refuse(using: input, reason: .insufficientConfidence)
        }

        // -------------------------------------------------------
        // FORCED REFUSAL (EXPLICIT OVERRIDE)
        // -------------------------------------------------------

        if let forced = input.refusalReason {
            if state != .shotFinalized && state != .refused {
                Log.info(
                    .shot,
                    "shot_force_refuse t=\(fmt(input.timestampSec)) reason=\(forced)"
                )
                return refuse(using: input, reason: forced)
            }
            return nil
        }

        // -------------------------------------------------------
        // HARD OBSERVABILITY GATES (FAIL CLOSED)
        // -------------------------------------------------------

        if !input.captureValid || !input.rsObservable {
            Log.info(
                .shot,
                "shot_observability_refuse t=\(fmt(input.timestampSec)) " +
                "captureValid=\(input.captureValid) rsObservable=\(input.rsObservable)"
            )
            return refuse(using: input, reason: .insufficientConfidence)
        }

        // -------------------------------------------------------
        // TERMINAL STATES — WAIT FOR QUIET RESET
        // -------------------------------------------------------

        if state == .shotFinalized || state == .refused {
            if input.motionDensityPhase == .idle {
                reset()
            }
            return nil
        }

        // -------------------------------------------------------
        // STATE MACHINE (NO DISCOVERY)
        // -------------------------------------------------------

        switch state {

        case .idle:
            if input.eligibleForShot {
                beginShot(at: input.timestampSec)
            }

        case .preImpact:
            if input.motionDensityPhase == .impact {
                impactTimestamp = input.timestampSec
                transition(to: .impactObserved, at: input.timestampSec)
            }

        case .impactObserved:
            if input.motionDensityPhase == .separation {
                transition(to: .postImpact, at: input.timestampSec)
            }

        case .postImpact:
            // ACCEPTANCE IS INTENTIONALLY FROZEN IN V1
            if !input.confirmedByUpstream {
                Log.info(
                    .shot,
                    "shot_refuse_unconfirmed t=\(fmt(input.timestampSec))"
                )
                return refuse(using: input, reason: .insufficientConfidence)
            }

            return finalize(using: input)

        case .shotFinalized, .refused:
            break
        }

        return nil
    }

    // MARK: - Transitions

    private func beginShot(at t: Double) {
        startTimestamp = t
        impactTimestamp = nil
        transition(to: .preImpact, at: t)
    }

    private func finalize(using input: ShotLifecycleInput) -> ShotLifecycleRecord {
        transition(to: .shotFinalized, at: input.timestampSec)

        let record = ShotLifecycleRecord(
            shotId: nextShotId,
            startTimestamp: startTimestamp ?? input.timestampSec,
            impactTimestamp: impactTimestamp,
            endTimestamp: input.timestampSec,
            refused: false,
            refusalReason: nil,
            finalState: .shotFinalized
        )

        advanceShotId()
        return record
    }

    private func refuse(
        using input: ShotLifecycleInput,
        reason: RefusalReason
    ) -> ShotLifecycleRecord {

        transition(to: .refused, at: input.timestampSec)

        let record = ShotLifecycleRecord(
            shotId: nextShotId,
            startTimestamp: startTimestamp ?? input.timestampSec,
            impactTimestamp: impactTimestamp,
            endTimestamp: input.timestampSec,
            refused: true,
            refusalReason: reason,
            finalState: .refused
        )

        advanceShotId()
        return record
    }

    private func transition(
        to newState: ShotLifecycleState,
        at t: Double
    ) {
        let from = state
        state = newState
        lastStateChangeTimestamp = t

        Log.info(
            .shot,
            "shot_state_transition t=\(fmt(t)) from=\(from.rawValue) to=\(newState.rawValue)"
        )
    }

    // MARK: - Reset

    private func reset() {
        state = .idle
        startTimestamp = nil
        impactTimestamp = nil
        lastStateChangeTimestamp = nil
    }

    private func advanceShotId() {
        nextShotId += 1
        reset()
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
