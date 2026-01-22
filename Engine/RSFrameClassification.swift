//
//  RSFrameClassification.swift
//  LaunchLab
//
//  Single-frame RS observability outcome.
//

import Foundation

enum RSFrameClassification {

    /// RS observables are internally consistent and locally anchored.
    /// This does NOT imply a shot — only that physics are preserved.
    case observable

    /// RS observables exist but cannot be uniquely interpreted.
    case refused(RSRefusalReason)
}
