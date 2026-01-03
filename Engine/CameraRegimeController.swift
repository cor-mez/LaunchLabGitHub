//
//  CameraRegimeController.swift
//  LaunchLab
//
//  Tracks camera photometric stability over time.
//  Read-only signal used to REFUSE authority when unstable.
//  Does NOT grant authority.
//

import Foundation

final class CameraRegimeController {

    enum Regime: String {
        case stable
        case unstable
    }

    // MARK: - Parameters

    /// Minimum time camera must remain stable before trusted
    private let requiredStableDurationSec: Double = 0.30

    // MARK: - State

    private(set) var regime: Regime = .unstable
    private var lastUnstableTime: Double?
    private var lastStableTime: Double?

    // MARK: - Public API

    var isStable: Bool {
        return regime == .stable
    }

    func reset() {
        regime = .unstable
        lastUnstableTime = nil
        lastStableTime = nil
    }

    /// Called when a global photometric disturbance is observed
    func markUnstable(at timestampSec: Double) {
        regime = .unstable
        lastUnstableTime = timestampSec
        lastStableTime = nil
    }

    /// Called every frame; transitions to stable only after cooldown
    func markStableIfEligible(at timestampSec: Double) {

        guard regime == .unstable else { return }

        guard let lastBad = lastUnstableTime else {
            // No instability recorded yet → allow stabilization clock
            lastStableTime = timestampSec
            return
        }

        let dt = timestampSec - lastBad
        guard dt >= requiredStableDurationSec else { return }

        regime = .stable
        lastStableTime = timestampSec
        Log.info(.shot, "[CAMERA] regime=stable")
    }
}
