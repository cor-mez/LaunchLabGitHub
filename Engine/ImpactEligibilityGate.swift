//
//  ImpactEligibilityGate.swift
//  LaunchLab
//
//  Impact Eligibility Gate (V1)
//
//  Purpose:
//  Decide whether it is even *plausible* for an impact to occur
//  at the current moment.
//
//  This gate is intentionally simple and conservative.
//  It does NOT detect impact.
//  It only decides whether impact detection is allowed.
//
//  Runs BEFORE ImpactSignatureLogger
//

import Foundation

final class ImpactEligibilityGate {

    // MARK: - Tunables (conservative defaults)

    /// Frames of stable presence required before impact is allowed
    private let minPresenceFrames: Int = 6

    /// Minimum raw speed to consider an impulse meaningful
    private let minImpactSpeedPxPerSec: Double = 50.0

    /// Minimum impulse ratio (spike vs baseline)
    private let minImpulseRatio: Double = 3.5

    // MARK: - State

    private var presenceStableFrames: Int = 0
    private var lastEligible: Bool = false

    // MARK: - Reset

    func reset() {
        presenceStableFrames = 0
        lastEligible = false
    }

    // MARK: - Update

    func update(
        presenceOk: Bool,
        instantaneousPxPerSec: Double,
        impulseRatio: Double?
    ) -> Bool {

        // Track presence stability
        if presenceOk {
            presenceStableFrames += 1
        } else {
            presenceStableFrames = 0
        }

        let eligible =
            presenceStableFrames >= minPresenceFrames &&
            instantaneousPxPerSec >= minImpactSpeedPxPerSec &&
            (impulseRatio ?? 0) >= minImpulseRatio

        // Transition-only logging
        if eligible != lastEligible {
            if eligible {
                Log.info(
                    .shot,
                    "PHASE impact_eligibility_on " +
                    "presenceFrames=\(presenceStableFrames) " +
                    "px_s=\(String(format: "%.1f", instantaneousPxPerSec)) " +
                    "ratio=\(String(format: "%.2f", impulseRatio ?? 0))"
                )
            } else {
                Log.info(
                    .shot,
                    "PHASE impact_eligibility_off " +
                    "presenceFrames=\(presenceStableFrames)"
                )
            }
        }

        lastEligible = eligible
        return eligible
    }
}
