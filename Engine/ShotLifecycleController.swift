//
//  ShotLifecycleController.swift
//  LaunchLab
//
//  Deterministic shot lifecycle state machine (V1)
//  Motion-first. BallLock used for confirmation only.
//  Engine-only, activity-logged, UI-agnostic.
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

// MARK: - Configuration

struct ShotLifecycleConfig: Equatable {
    let acquiredThreshold: Float
    let trackingFloor: Float
    let minValidShotSpeedPxPerSec: Double

    init(
        acquiredThreshold: Float = 6.0,
        trackingFloor: Float = 2.0,
        minValidShotSpeedPxPerSec: Double = 400.0
    ) {
        self.acquiredThreshold = acquiredThreshold
        self.trackingFloor = trackingFloor
        self.minValidShotSpeedPxPerSec = minValidShotSpeedPxPerSec
    }
}

// MARK: - Input Snapshot

struct ShotLifecycleInput {
    let timestampSec: Double
    let ballLockConfidence: Float
    let motionDensityPhase: MotionDensityPhase
    let ballSpeedPxPerSec: Double?
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

// MARK: - Controller

final class ShotLifecycleController {

    private(set) var state: ShotLifecycleState = .idle
    private let config: ShotLifecycleConfig

    private var nextShotId: Int = 1

    private var startTimestamp: Double?
    private var impactTimestamp: Double?
    private var endTimestamp: Double?

    private var balllockConfidenceAtStart: Float?
    private var motionDensityPhases: [MotionDensityPhase] = []
    private var peakBallSpeedPxPerSec: Double?

    init(config: ShotLifecycleConfig = ShotLifecycleConfig()) {
        self.config = config
    }

    // MARK: - Update

    func update(_ input: ShotLifecycleInput) -> ShotLifecycleRecord? {

        // ---------------------------------------------------------------
        // Forced refusal path (MECHANICAL)
        // If any upstream guard provides a refusalReason, we terminate now.
        // ---------------------------------------------------------------
        if let forcedReason = input.refusalReason {
            // If we are already terminal, do nothing.
            if state == .shotFinalized || state == .refused {
                return nil
            }

            // If we haven't started a shot yet, startTimestamp should still be meaningful for logs/records.
            if startTimestamp == nil {
                startTimestamp = input.timestampSec
                balllockConfidenceAtStart = input.ballLockConfidence
            }

            Log.info(
                .shot,
                "shot_force_refuse t=\(fmt(input.timestampSec)) reason=\(String(describing: forcedReason))"
            )
            return refuse(using: input, reason: forcedReason)
        }

        recordMotionPhase(input.motionDensityPhase)

        // Accumulate peak speed only after impact
        if state == .postImpact, let v = input.ballSpeedPxPerSec {
            if peakBallSpeedPxPerSec == nil || v > peakBallSpeedPxPerSec! {
                peakBallSpeedPxPerSec = v
            }
        }

        // Reset after terminal states once scene is quiet
        if state == .shotFinalized || state == .refused {
            if input.motionDensityPhase == .idle &&
               input.ballLockConfidence < config.acquiredThreshold {
                reset()
            }
            return nil
        }

        switch state {

        // ---------------------------------------------------------------
        // IDLE → PRE-IMPACT (MOTION-FIRST)
        // ---------------------------------------------------------------
        case .idle:
            if input.motionDensityPhase == .impact,
               let v = input.ballSpeedPxPerSec,
               v >= config.minValidShotSpeedPxPerSec {

                Log.info(
                    .shot,
                    "shot_start_allowed t=\(fmt(input.timestampSec)) v_px_s=\(fmt(v))"
                )

                beginShot(using: input)
            }

        // ---------------------------------------------------------------
        // PRE-IMPACT
        // ---------------------------------------------------------------
        case .preImpact:
            if input.motionDensityPhase == .impact {
                impactTimestamp = input.timestampSec
                transition(to: .impactObserved, using: input)
            }

        // ---------------------------------------------------------------
        // IMPACT OBSERVED
        // ---------------------------------------------------------------
        case .impactObserved:
            if input.motionDensityPhase == .separation {
                transition(to: .postImpact, using: input)
            }

        // ---------------------------------------------------------------
        // POST-IMPACT
        // ---------------------------------------------------------------
        case .postImpact:
            if input.motionDensityPhase == .stabilized {

                guard let peak = peakBallSpeedPxPerSec,
                      peak >= config.minValidShotSpeedPxPerSec else {

                    Log.info(
                        .shot,
                        "shot_refused t=\(fmt(input.timestampSec)) " +
                        "reason=insufficient_speed peak_px_s=\(peakBallSpeedPxPerSec.map { fmt($0) } ?? "n/a")"
                    )
                    return refuse(using: input, reason: .insufficientConfidence)
                }

                return finalize(using: input)
            }

        case .shotFinalized, .refused:
            break
        }

        return nil
    }

    func reset() {
        state = .idle
        clearState()
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

        let record = buildRecord(finalState: .shotFinalized, refusalReason: nil)
        advanceShotId()
        return record
    }

    private func refuse(
        using input: ShotLifecycleInput,
        reason: RefusalReason
    ) -> ShotLifecycleRecord {

        endTimestamp = input.timestampSec
        transition(to: .refused, using: input, refusalReason: reason)

        let record = buildRecord(finalState: .refused, refusalReason: reason)
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
                "from=\(from.rawValue) to=\(newState.rawValue) " +
                "reason=\(String(describing: rr))"
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

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
