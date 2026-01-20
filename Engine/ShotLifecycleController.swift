//
//  ShotLifecycleController.swift
//  LaunchLab
//
//  Canonical shot authority spine (V1)
//  Refusal-first. No discovery logic.
//  Accepts or refuses only on explicit evidence.
//  Engine-only, UI-agnostic.
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

    // -----------------------------------------------------------
    // HARD OBSERVABILITY GATES (must be explicit)
    // -----------------------------------------------------------
    let captureValid: Bool
    let rsObservable: Bool

    // -----------------------------------------------------------
    // UPSTREAM EVIDENCE (authority does not infer)
    // -----------------------------------------------------------
    let eligibleForShot: Bool
    let confirmedByUpstream: Bool

    // -----------------------------------------------------------
    // Legacy context (logging only)
    // -----------------------------------------------------------
    let ballLockConfidence: Float
    let motionDensityPhase: MotionDensityPhase
    let ballSpeedPxPerSec: Double?

    // -----------------------------------------------------------
    // Forced refusal (explicit override)
    // -----------------------------------------------------------
    let refusalReason: RefusalReason?
}

// MARK: - Record

struct ShotLifecycleRecord {
    let shotId: Int
    let startTimestamp: Double
    let impactTimestamp: Double?
    let endTimestamp: Double
    let balllockConfidenceAtStart: Float
    let motionDensitySummary: String
    let peakBallSpeedPxPerSec: Double?
    let refused: Bool
    let refusalReason: RefusalReason?
    let finalState: ShotLifecycleState
}

// MARK: - Controller (SINGULAR AUTHORITY)

final class ShotLifecycleController {

    // -----------------------------------------------------------
    // State
    // -----------------------------------------------------------

    private(set) var state: ShotLifecycleState = .idle
    private var nextShotId: Int = 1

    private var startTimestamp: Double?
    private var impactTimestamp: Double?
    private var endTimestamp: Double?

    private var balllockConfidenceAtStart: Float?
    private var motionDensityPhases: [MotionDensityPhase] = []
    private var peakBallSpeedPxPerSec: Double?

    // -----------------------------------------------------------
    // Update (ONLY ENTRY POINT)
    // -----------------------------------------------------------

    func update(_ input: ShotLifecycleInput) -> ShotLifecycleRecord? {

        // -------------------------------------------------------
        // FORCED REFUSAL (absolute)
        // -------------------------------------------------------

        if let forcedReason = input.refusalReason,
           state != .shotFinalized,
           state != .refused {

            Log.info(
                .shot,
                "shot_force_refuse t=\(fmt(input.timestampSec)) reason=\(forcedReason)"
            )

            return refuse(using: input, reason: forcedReason)
        }

        // -------------------------------------------------------
        // HARD OBSERVABILITY GATES (REFUSAL-FIRST)
        // -------------------------------------------------------
        // IMPORTANT:
        // ShotLifecycleController does NOT create RefusalReason.
        // Upstream must populate input.refusalReason.
        // -------------------------------------------------------

        if !input.captureValid || !input.rsObservable {
            return input.refusalReason.map {
                refuse(using: input, reason: $0)
            }
        }

        // -------------------------------------------------------
        // RECORD CONTEXT (NON-AUTHORITATIVE)
        // -------------------------------------------------------

        recordMotionPhase(input.motionDensityPhase)

        if state == .postImpact, let v = input.ballSpeedPxPerSec {
            if peakBallSpeedPxPerSec == nil || v > peakBallSpeedPxPerSec! {
                peakBallSpeedPxPerSec = v
            }
        }

        // -------------------------------------------------------
        // TERMINAL STATES (wait for quiet reset)
        // -------------------------------------------------------

        if state == .shotFinalized || state == .refused {
            if input.motionDensityPhase == .idle && input.ballLockConfidence < 1.0 {
                reset()
            }
            return nil
        }

        // -------------------------------------------------------
        // STATE MACHINE (AUTHORITY ONLY — NO DISCOVERY)
        // -------------------------------------------------------

        switch state {

        case .idle:
            if input.eligibleForShot {
                beginShot(using: input)
            }

        case .preImpact:
            if input.motionDensityPhase == .impact {
                impactTimestamp = input.timestampSec
                transition(to: .impactObserved, using: input)
            }

        case .impactObserved:
            if input.motionDensityPhase == .separation {
                transition(to: .postImpact, using: input)
            }

        case .postImpact:
            if !input.confirmedByUpstream {
                return input.refusalReason.map {
                    refuse(using: input, reason: $0)
                }
            }
            return finalize(using: input)

        case .shotFinalized, .refused:
            break
        }

        return nil
    }

    // MARK: - Transitions

    private func beginShot(using input: ShotLifecycleInput) {
        startTimestamp = input.timestampSec
        balllockConfidenceAtStart = input.ballLockConfidence
        impactTimestamp = nil
        peakBallSpeedPxPerSec = nil
        motionDensityPhases.removeAll()
        transition(to: .preImpact, using: input)
    }

    private func finalize(using input: ShotLifecycleInput) -> ShotLifecycleRecord {
        endTimestamp = input.timestampSec
        transition(to: .shotFinalized, using: input)

        let record = buildRecord(
            finalState: .shotFinalized,
            refusalReason: nil
        )
        advanceShotId()
        return record
    }

    private func refuse(
        using input: ShotLifecycleInput,
        reason: RefusalReason
    ) -> ShotLifecycleRecord {

        endTimestamp = input.timestampSec
        transition(to: .refused, using: input, refusalReason: reason)

        let record = buildRecord(
            finalState: .refused,
            refusalReason: reason
        )
        advanceShotId()
        return record
    }

    private func transition(
        to newState: ShotLifecycleState,
        using input: ShotLifecycleInput,
        refusalReason: RefusalReason? = nil
    ) {
        let from = state
        state = newState

        if let rr = refusalReason {
            Log.info(
                .shot,
                "shot_state_transition t=\(fmt(input.timestampSec)) " +
                "from=\(from.rawValue) to=\(newState.rawValue) reason=\(rr)"
            )
        } else {
            Log.info(
                .shot,
                "shot_state_transition t=\(fmt(input.timestampSec)) " +
                "from=\(from.rawValue) to=\(newState.rawValue)"
            )
        }
    }

    // MARK: - Record Assembly

    private func buildRecord(
        finalState: ShotLifecycleState,
        refusalReason: RefusalReason?
    ) -> ShotLifecycleRecord {

        ShotLifecycleRecord(
            shotId: nextShotId,
            startTimestamp: startTimestamp ?? 0,
            impactTimestamp: impactTimestamp,
            endTimestamp: endTimestamp ?? startTimestamp ?? 0,
            balllockConfidenceAtStart: balllockConfidenceAtStart ?? 0,
            motionDensitySummary: motionDensityPhases
                .map { $0.rawValue }
                .joined(separator: "→"),
            peakBallSpeedPxPerSec: peakBallSpeedPxPerSec,
            refused: finalState == .refused,
            refusalReason: refusalReason,
            finalState: finalState
        )
    }

    // MARK: - Reset Helpers

    private func advanceShotId() {
        nextShotId += 1
        clearState()
    }

    private func clearState() {
        startTimestamp = nil
        impactTimestamp = nil
        endTimestamp = nil
        balllockConfidenceAtStart = nil
        peakBallSpeedPxPerSec = nil
        motionDensityPhases.removeAll()
    }

    private func recordMotionPhase(_ phase: MotionDensityPhase) {
        if motionDensityPhases.last != phase {
            motionDensityPhases.append(phase)
        }
    }

    private func reset() {
        state = .idle
        clearState()
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
