//
//  ImpactImpulseAuthority.swift
//  LaunchLab
//
//  Impulse-Based Impact Authority
//

import CoreGraphics

final class ImpactImpulseAuthority {

    // MARK: - Tunables (conservative)

    private let minDeltaSpeedPxPerSec: Double = 1200.0
    private let maxImpulseFrames: Int = 2

    // MARK: - State

    private var lastSpeed: Double?
    private var impulseFramesRemaining: Int = 0
    private var fired: Bool = false

    // MARK: - Reset

    func reset() {
        lastSpeed = nil
        impulseFramesRemaining = 0
        fired = false
    }

    // MARK: - Update

    /// Returns true exactly once when an impulse is observed
    func update(speedPxPerSec: Double) -> Bool {

        defer { lastSpeed = speedPxPerSec }

        guard !fired else { return false }

        guard let prev = lastSpeed else {
            return false
        }

        let delta = speedPxPerSec - prev

        if delta >= minDeltaSpeedPxPerSec {
            impulseFramesRemaining = maxImpulseFrames
            fired = true

            Log.info(.finalShot, "[SHOT] impulse_detected Δv=\(Int(delta))px/s")
            return true
        }

        if impulseFramesRemaining > 0 {
            impulseFramesRemaining -= 1
        }

        return false
    }
}
