//
//  ImpactConfirmationGate.swift
//  LaunchLab
//
//  Impact Onset Observability Module (V1)
//
//  ROLE (STRICT):
//  - Observe entry into a motion regime consistent with impact
//  - Reject camera-global motion
//  - Produce observational evidence only
//  - NEVER confirm, authorize, or finalize a shot
//

import Foundation
import CoreGraphics

/// Observational impact-onset evidence.
/// Carries facts, not decisions.
struct ImpactObservation {

    let activeFrames: Int
    let instantaneousPxPerSec: Double
    let centerDriftPx: Double
}

/// Observes motion patterns consistent with impact onset.
/// All authority is deferred to ShotLifecycleController.
final class ImpactConfirmationGate {

    // MARK: - Parameters (OBSERVATIONAL)

    private let requiredActiveFrames: Int = 3
    private let activityThresholdPxPerSec: Double = 6.0
    private let maxIdleFrames: Int = 2
    private let maxCenterDriftPx: Double = 3.0

    // MARK: - State (OBSERVATIONAL ONLY)

    private var activeFrames: Int = 0
    private var idleFrames: Int = 0
    private var anchorCenter: CGPoint?

    // MARK: - Reset

    func reset() {
        activeFrames = 0
        idleFrames = 0
        anchorCenter = nil
    }

    // MARK: - Update

    /// Observe impact-onset characteristics for the current frame.
    /// Returns an ImpactObservation when minimum structure exists,
    /// otherwise returns nil.
    func observe(
        presenceOk: Bool,
        center: CGPoint,
        instantaneousPxPerSec: Double
    ) -> ImpactObservation? {

        guard presenceOk else {
            reset()
            return nil
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
            return nil
        }

        guard activeFrames >= requiredActiveFrames else {
            return nil
        }

        Log.info(
            .shot,
            "[OBSERVE] impact_onset frames=\(activeFrames) px_s=\(fmt1(instantaneousPxPerSec)) drift=\(fmt2(drift))"
        )

        return ImpactObservation(
            activeFrames: activeFrames,
            instantaneousPxPerSec: instantaneousPxPerSec,
            centerDriftPx: drift
        )
    }

    // MARK: - Formatting

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func fmt2(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
