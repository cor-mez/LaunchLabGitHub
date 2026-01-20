//
//  UnitConverter.swift
//  LaunchLab
//
//  Canonical unit conversions for the engine.
//  Deterministic, auditable, no heuristics.
//  Engine-pure: no UI or Founder model dependencies.
//

import Foundation

enum UnitConverter {

    // MARK: - Constants

    static let metersPerSecondToMPH: Double = 2.236936
    static let metersToYardsFactor: Double = 1.09361

    // MARK: - Speed

    /// Convert pixel velocity to MPH using an explicit pixel-to-meter scale.
    /// Returns nil if scale is invalid.
    static func pxPerSecToMPH(
        _ pxPerSec: Double,
        pixelsPerMeter: Double
    ) -> Double? {
        guard pixelsPerMeter > 0 else { return nil }
        let metersPerSec = pxPerSec / pixelsPerMeter
        return metersPerSec * metersPerSecondToMPH
    }

    // MARK: - Distance

    static func metersToYards(_ meters: Double) -> Double {
        meters * metersToYardsFactor
    }
}
