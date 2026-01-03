//
//  ImpactSignatureLogger.swift
//  LaunchLab
//
//  Observes impact-like energy injection.
//  Does NOT validate flight.
//

import CoreGraphics

final class ImpactSignatureLogger {

    private let minImpulsePxPerSec: Double = 12.0

    private var fired: Bool = false

    func reset() {
        fired = false
    }

    /// Returns true exactly once per shot attempt
    func observe(
        timestampSec: Double,
        instantaneousPxPerSec: Double,
        presenceOk: Bool
    ) -> Bool {

        guard !fired else { return false }
        guard presenceOk else { return false }

        if instantaneousPxPerSec >= minImpulsePxPerSec {
            fired = true
            Log.info(.shot, "IMPACT signature_observed")
            return true
        }

        return false
    }
}
