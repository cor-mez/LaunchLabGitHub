//
//  PhaseObservabilityLogger.swift
//  LaunchLab
//
//  Observational-only phase labeling.
//  No authority changes. No lifecycle changes. No tuning requests.
//
//  Goal: emit sparse, readable phase transitions so we can answer:
//  "Which phase never occurred?" rather than "Why didn't it detect?"
//

import Foundation
import CoreGraphics

final class PhaseObservabilityLogger {

    enum Phase: String, Sendable {
        case sceneQuiet      = "scene_quiet"
        case presence        = "presence"
        case disturbance     = "disturbance"
        case impactSignature = "impact_signature"
        case separation      = "separation"
    }

    // MARK: - Configuration (LOGGING ONLY)

    /// Prevent phase spam when conditions oscillate rapidly.
    private let emitCooldownSec: Double = 0.15

    /// Conservative separation window: only label separation if ball is lost soon after an impact signature.
    private let separationWindowSec: Double = 0.25

    // MARK: - State

    private var lastPhase: Phase?
    private var lastEmitTime: Double?

    private var lastImpactTime: Double?

    init() {}

    func reset() {
        lastPhase = nil
        lastEmitTime = nil
        lastImpactTime = nil
    }

    func observe(
        timestampSec: Double,
        presenceOk: Bool,
        presenceAbsenceReason: String?,
        ballLockConfidence: Float,
        center: CGPoint?,
        instantaneousPxPerSec: Double,
        quietCandidateFrames: Int,
        impactEvent: ImpactSignatureEvent?
    ) {

        // Update impact memory first (used for separation inference).
        if let impactEvent {
            lastImpactTime = impactEvent.timestampSec
        }

        let ballPresent = (center != nil)
        let quietCandidate = (quietCandidateFrames > 0)

        // Conservative "separation": ball is lost shortly after impact.
        let separationNow: Bool = {
            guard let tImpact = lastImpactTime else { return false }
            let dt = timestampSec - tImpact
            guard dt >= 0, dt <= separationWindowSec else { return false }
            // Separation only when we actually lose the ball.
            return !ballPresent
        }()

        let phaseNow: Phase = {
            if impactEvent != nil { return .impactSignature }
            if separationNow       { return .separation }
            if presenceOk {
                // If quietGate thinks the scene is quiet enough to be a candidate,
                // we call this "presence" (ball exists + stable baseline).
                return quietCandidate ? .presence : .disturbance
            }
            // When not present, we keep this coarse: "scene quiet / baseline".
            return .sceneQuiet
        }()

        // Emit only on transitions (with cooldown).
        let cooledDown: Bool = {
            guard let last = lastEmitTime else { return true }
            return (timestampSec - last) >= emitCooldownSec
        }()

        guard cooledDown && phaseNow != lastPhase else { return }

        lastPhase = phaseNow
        lastEmitTime = timestampSec

        // Compose a readable, consistent log line.
        // Keep it compact; don't duplicate other loggers’ details unless helpful.
        var msg = "PHASE \(phaseNow.rawValue) "
        msg += "t=\(fmt3(timestampSec)) "
        msg += "conf=\(fmt1(ballLockConfidence)) "
        msg += "qf=\(quietCandidateFrames) "

        switch phaseNow {

        case .sceneQuiet:
            msg += "presence=\(presenceOk)"
            if !presenceOk, let r = presenceAbsenceReason {
                msg += " absent_reason=\(r)"
            }

        case .presence:
            // Presence is stable baseline, not motion.
            msg += "presence=\(presenceOk)"

        case .disturbance:
            msg += "px_s=\(fmt1(instantaneousPxPerSec))"
            if !presenceOk, let r = presenceAbsenceReason {
                msg += " absent_reason=\(r)"
            }

        case .impactSignature:
            if let e = impactEvent {
                msg += "v=\(fmt3(e.speedPxPerSec)) "
                msg += "dv=\(fmt3(e.deltaSpeedPxPerSec)) "
                msg += "dir_dot=\(fmt3(e.directionDot))"
            }

        case .separation:
            if let tImpact = lastImpactTime {
                let dt = timestampSec - tImpact
                msg += "dt=\(fmt3(dt)) reason=ball_lost_after_impact"
            } else {
                msg += "reason=ball_lost_after_impact"
            }
        }

        Log.info(.shot, msg)
    }

    // MARK: - Formatting

    private func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func fmt1(_ v: Float)  -> String { String(format: "%.1f", v) }
}
