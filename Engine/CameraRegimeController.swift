//
//  CameraRegimeController.swift
//  LaunchLab
//
//  Camera Regime OBSERVER (V1)
//
//  ROLE (STRICT):
//  - Observe photometric / exposure stability over time
//  - Emit a read-only stability signal
//  - NEVER grant authority
//  - Used only as a REFUSAL gate upstream of ShotLifecycleController
//

import Foundation

final class CameraRegimeController {

    // -----------------------------------------------------------
    // MARK: - Regime State
    // -----------------------------------------------------------

    enum Regime: String {
        case stable
        case unstable
    }

    // -----------------------------------------------------------
    // MARK: - Parameters (CONSERVATIVE)
// -----------------------------------------------------------

    /// Minimum time camera must remain stable before considered observable
    private let requiredStableDurationSec: Double = 0.30

    // -----------------------------------------------------------
    // MARK: - State (OBSERVATIONAL)
    // -----------------------------------------------------------

    private(set) var regime: Regime = .unstable
    private var lastUnstableTime: Double?
    private var lastStableTransitionTime: Double?

    // -----------------------------------------------------------
    // MARK: - Public Observability
    // -----------------------------------------------------------

    /// Read-only observability signal.
    /// TRUE means "not unstable for long enough".
    /// FALSE means "cannot trust photometry yet".
    var isStable: Bool {
        regime == .stable
    }

    /// Reason string suitable for refusal logging.
    var instabilityReason: String? {
        guard regime == .unstable else { return nil }
        return "camera_photometry_unstable"
    }

    // -----------------------------------------------------------
    // MARK: - Lifecycle
    // -----------------------------------------------------------

    func reset() {
        regime = .unstable
        lastUnstableTime = nil
        lastStableTransitionTime = nil
    }

    /// Called when a global photometric disturbance is observed.
    /// This immediately invalidates observability.
    func markUnstable(at timestampSec: Double) {

        // Avoid log spam if already unstable
        if regime != .unstable {
            Log.info(.camera, "camera_regime=unstable t=\(fmt(timestampSec))")
        }

        regime = .unstable
        lastUnstableTime = timestampSec
        lastStableTransitionTime = nil
    }

    /// Called every frame when no instability is observed.
    /// Transitions to stable only after the required quiet window.
    func markStableIfEligible(at timestampSec: Double) {

        guard regime == .unstable else { return }

        guard let lastBad = lastUnstableTime else {
            // No instability recorded yet; begin stability clock
            lastStableTransitionTime = timestampSec
            return
        }

        let dt = timestampSec - lastBad
        guard dt >= requiredStableDurationSec else { return }

        regime = .stable
        lastStableTransitionTime = timestampSec

        Log.info(
            .camera,
            "camera_regime=stable t=\(fmt(timestampSec)) quiet_sec=\(fmt(dt))"
        )
    }

    // -----------------------------------------------------------
    // MARK: - Formatting
    // -----------------------------------------------------------

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
