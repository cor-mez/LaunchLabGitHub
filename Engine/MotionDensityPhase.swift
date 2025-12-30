//
//  MotionDensityPhase.swift
//  LaunchLab
//
//  Canonical motion/density phase signal for shot lifecycle (V1)
//

import Foundation

enum MotionDensityPhase: String {
    case idle
    case approach
    case impact
    case separation
    case stabilized

    /// Any phase that indicates active shot-related motion
    var isNonIdleActivity: Bool {
        self != .idle
    }
}
