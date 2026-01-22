//
//  ImpactSignatureLogger.swift
//  LaunchLab
//
//  PHASE 2 — Per-frame impact-like impulse observability
//
//  ROLE (STRICT):
//  - Evaluate ONE frame only
//  - No temporal memory
//  - No latching
//  - No authority
//  - No logging
//  - Emit telemetry facts only
//

import Foundation

final class ImpactSignatureLogger {

    // ---------------------------------------------------------
    // Configuration (epistemic, not heuristic)
    // ---------------------------------------------------------

    /// Minimum instantaneous motion required to consider
    /// an impulse-like energy injection.
    ///
    /// NOTE:
    /// This does NOT imply a ball strike.
    /// It only states that motion energy crossed a threshold.
    private let minImpulsePxPerSec: Double = 12.0

    // ---------------------------------------------------------
    // Per-frame evaluation
    // ---------------------------------------------------------

    /// Evaluates a single frame for impulse-like motion.
    ///
    /// Returns:
    /// - `true`  → impulse-like energy observed
    /// - `false` → no impulse observed
    ///
    /// This result must be consumed by a higher-level
    /// observability classifier. This class makes NO decisions.
    @inline(__always)
    func evaluate(
        instantaneousPxPerSec: Double,
        presenceOk: Bool
    ) -> Bool {

        guard presenceOk else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x30   // presence not satisfied
            )
            return false
        }

        let impulse = instantaneousPxPerSec >= minImpulsePxPerSec

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: impulse ? 0x31 : 0x32,
            valueA: Float(instantaneousPxPerSec),
            valueB: impulse ? 1.0 : 0.0
        )

        return impulse
    }
}
