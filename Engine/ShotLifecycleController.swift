//
//  ShotLifecycleController.swift
//  LaunchLab
//
//  Canonical Shot Authority Spine (V1)
//
//  PROPERTIES:
//  - Single authority
//  - Refusal-first
//  - Actor-isolated (thread-safe)
//  - No discovery logic
//  - Guaranteed termination (deadman timer)
//  - Acceptance intentionally frozen
//

import Foundation

// MARK: - Lifecycle States

enum ShotLifecycleState: String {
    case idle
    case awaitingImpact
    case awaitingPostImpact
    case shotFinalized
    case refused
}

// MARK: - Input Snapshot (AUTHORITY-ONLY)

struct ShotLifecycleInput {

    let timestampSec: Double

    // HARD OBSERVABILITY
    let captureValid: Bool
    let rsObservable: Bool

    // UPSTREAM EVIDENCE (FACTS ONLY)
    let eligibleForShot: Bool
    let impactObserved: Bool
    let postImpactObserved: Bool
    let confirmedByUpstream: Bool   // intentionally false in V1

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

actor ShotLifecycleController {

    // -----------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------

    /// Maximum allowed non-idle lifetime before forced refusal (seconds)
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

            return refuse(at: input.timestampSec, reason: .lifecycleTimeout)
        }

        // -------------------------------------------------------
        // FORCED REFUSAL (EXPLICIT OVERRIDE)
        // -------------------------------------------------------

        if let forced = input.refusalReason,
           state != .shotFinalized && state != .refused {

            Log.info(
                .shot,
                "shot_force_refuse t=\(fmt(input.timestampSec)) reason=\(forced)"
            )

            return refuse(at: input.timestampSec, reason: forced)
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
            return refuse(at: input.timestampSec, reason: .insufficientConfidence)
        }

        // -------------------------------------------------------
        // TERMINAL STATES — WAIT FOR QUIET RESET
        // -------------------------------------------------------

        if state == .shotFinalized || state == .refused {
            return nil
        }

        // -------------------------------------------------------
        // STATE MACHINE (FACT-DRIVEN ONLY)
        // -------------------------------------------------------

        switch state {

        case .idle:
            if input.eligibleForShot {
                startTimestamp = input.timestampSec
                transition(to: .awaitingImpact, at: input.timestampSec)
            }

        case .awaitingImpact:
            if input.impactObserved {
                impactTimestamp = input.timestampSec
                transition(to: .awaitingPostImpact, at: input.timestampSec)
            }

        case .awaitingPostImpact:
            if input.postImpactObserved {

                // ACCEPTANCE FROZEN — require explicit upstream confirmation
                guard input.confirmedByUpstream else {
                    return refuse(at: input.timestampSec, reason: .insufficientConfidence)
                }

                return finalize(at: input.timestampSec)
            }

        case .shotFinalized, .refused:
            break
        }

        return nil
    }

    // MARK: - Finalization

    private func finalize(at t: Double) -> ShotLifecycleRecord {

        transition(to: .shotFinalized, at: t)

        let record = ShotLifecycleRecord(
            shotId: nextShotId,
            startTimestamp: startTimestamp ?? t,
            impactTimestamp: impactTimestamp,
            endTimestamp: t,
            refused: false,
            refusalReason: nil,
            finalState: .shotFinalized
        )

        advanceShotId()
        return record
    }

    private func refuse(
        at t: Double,
        reason: RefusalReason
    ) -> ShotLifecycleRecord {

        transition(to: .refused, at: t)

        let record = ShotLifecycleRecord(
            shotId: nextShotId,
            startTimestamp: startTimestamp ?? t,
            impactTimestamp: impactTimestamp,
            endTimestamp: t,
            refused: true,
            refusalReason: reason,
            finalState: .refused
        )

        advanceShotId()
        return record
    }

    // MARK: - State Helpers

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

    private func advanceShotId() {
        nextShotId += 1
        reset()
    }

    private func reset() {
        state = .idle
        startTimestamp = nil
        impactTimestamp = nil
        lastStateChangeTimestamp = nil
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
