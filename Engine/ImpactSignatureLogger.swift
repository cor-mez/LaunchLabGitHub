//
//  ImpactSignatureLogger.swift
//  LaunchLab
//
//  Observational-only logger.
//  Emits an "impact_sig" line when motion exhibits a sudden energy injection
//  and a directional discontinuity (Δv + dir dot break).
//
//  This does NOT gate authority. Logging only.
//

import Foundation
import CoreGraphics

/// A single detected "impact-like" signature derived from instantaneous motion deltas.
/// Intended for observability, not authority.
struct ImpactSignatureEvent: Sendable {
    let timestampSec: Double
    let speedPxPerSec: Double
    let deltaSpeedPxPerSec: Double
    let directionDot: Double
}

/// Observes instantaneous motion and logs sparse "impact_sig" events.
///
/// Notes:
/// - Uses minimal thresholds to avoid log spam.
/// - Resets automatically when `presenceOk == false`.
final class ImpactSignatureLogger {

    // MARK: - Tuning (LOGGING ONLY)

    /// Ignore extremely small speeds; mostly jitter/noise.
    private let minSpeedPxPerSec: Double = 5.0

    /// Minimum positive speed step to consider an impulse candidate.
    private let minDeltaSpeedPxPerSec: Double = 2.0

    /// A direction dot below this indicates meaningful direction change (negative is reversal).
    private let directionDotMax: Double = -0.15

    /// Always log very large Δv even if direction dot is not strongly negative.
    private let hardDeltaSpeedPxPerSec: Double = 15.0

    /// Prevent repeated events from the same microburst.
    private let emitCooldownSec: Double = 0.12

    // MARK: - State

    private var lastSpeed: Double?
    private var lastUnitVel: CGVector?
    private var lastEmitTime: Double?

    init() {}

    func reset() {
        lastSpeed = nil
        lastUnitVel = nil
        lastEmitTime = nil
    }

    /// Observe motion. Returns an `ImpactSignatureEvent` when a signature is detected.
    @discardableResult
    func observe(
        timestampSec: Double,
        instantaneousPxPerSec: Double,
        velocityPx: CGVector?,
        presenceOk: Bool
    ) -> ImpactSignatureEvent? {

        // If the system doesn't consider the ball present, we do not attempt to interpret motion.
        guard presenceOk else {
            reset()
            return nil
        }

        // Need a velocity vector to compute direction discontinuity.
        guard let v = velocityPx else {
            lastSpeed = instantaneousPxPerSec
            return nil
        }

        let speed = instantaneousPxPerSec
        guard speed >= minSpeedPxPerSec else {
            lastSpeed = speed
            lastUnitVel = unit(v)
            return nil
        }

        let u = unit(v)
        let dv: Double = {
            guard let last = lastSpeed else { return 0 }
            return speed - last
        }()

        let dirDot: Double = {
            guard let lastU = lastUnitVel else { return 1.0 }
            return dot(u, lastU)
        }()

        let cooledDown: Bool = {
            guard let last = lastEmitTime else { return true }
            return (timestampSec - last) >= emitCooldownSec
        }()

        let impulseCandidate = dv >= minDeltaSpeedPxPerSec
        let directionBreak   = dirDot <= directionDotMax
        let hardImpulse      = dv >= hardDeltaSpeedPxPerSec

        var event: ImpactSignatureEvent?

        if cooledDown && (hardImpulse || (impulseCandidate && directionBreak)) {

            event = ImpactSignatureEvent(
                timestampSec: timestampSec,
                speedPxPerSec: speed,
                deltaSpeedPxPerSec: dv,
                directionDot: dirDot
            )

            lastEmitTime = timestampSec

            Log.info(
                .shot,
                "impact_sig " +
                "t=\(fmt3(timestampSec)) " +
                "v=\(fmt3(speed)) " +
                "dv=\(fmt3(dv)) " +
                "dir_dot=\(fmt3(dirDot))"
            )
        }

        lastSpeed = speed
        lastUnitVel = u
        return event
    }

    // MARK: - Vector Math

    private func unit(_ v: CGVector) -> CGVector {
        let mag = hypot(Double(v.dx), Double(v.dy))
        guard mag > 0 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }

    private func dot(_ a: CGVector, _ b: CGVector) -> Double {
        Double(a.dx * b.dx + a.dy * b.dy)
    }

    // MARK: - Formatting

    private func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
}
