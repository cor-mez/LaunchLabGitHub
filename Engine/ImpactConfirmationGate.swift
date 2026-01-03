//
//  ImpactConfirmationGate.swift
//  LaunchLab
//
//  Confirms ENTRY into a motion regime.
//  Rejects camera-global motion.
//  Purpose: detect real impact onset, not violence.
//

import Foundation
import CoreGraphics

final class ImpactConfirmationGate {

    // MARK: - Parameters

    private let requiredActiveFrames: Int = 3
    private let activityThresholdPxPerSec: Double = 6.0
    private let maxIdleFrames: Int = 2
    private let maxCenterDriftPx: Double = 3.0

    // MARK: - State

    private var activeFrames: Int = 0
    private var idleFrames: Int = 0
    private var confirmed: Bool = false
    private var anchorCenter: CGPoint?

    // MARK: - Reset

    func reset() {
        activeFrames = 0
        idleFrames = 0
        confirmed = false
        anchorCenter = nil
    }

    // MARK: - Update

    /// Returns true exactly once when impact is confirmed
    func update(
        presenceOk: Bool,
        center: CGPoint,
        instantaneousPxPerSec: Double
    ) -> Bool {

        guard presenceOk else {
            reset()
            return false
        }

        if anchorCenter == nil {
            anchorCenter = center
        }

        let drift = hypot(
            center.x - anchorCenter!.x,
            center.y - anchorCenter!.y
        )

        let isActive =
            instantaneousPxPerSec >= activityThresholdPxPerSec &&
            drift <= maxCenterDriftPx

        if isActive {
            activeFrames += 1
            idleFrames = 0
        } else {
            idleFrames += 1
            activeFrames = 0
        }

        if idleFrames > maxIdleFrames {
            reset()
            return false
        }

        if !confirmed && activeFrames >= requiredActiveFrames {
            confirmed = true
            Log.info(.shot, "PHASE impact_confirmed")
            return true
        }

        return false
    }
}
