//
//  RSRowProfile.swift
//  LaunchLab
//
//  Per-row rolling shutter observability
//

import Foundation

struct RSRowProfile {

    /// Row index (top → bottom)
    let row: Int

    /// Mean absolute gradient magnitude in this row
    let gradientEnergy: Float

    /// Local contrast change (illumination-sensitive)
    let luminanceDelta: Float
}
