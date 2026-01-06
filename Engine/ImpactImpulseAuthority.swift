//
//  ImpactImpulseAuthority.swift
//  LaunchLab
//
//  Impulse-Based Impact Authority (OBSERVED → AUTHORITATIVE)
//

import CoreGraphics

final class ImpactImpulseAuthority {

    // Tunables (conservative)
    private let minDeltaSpeedPxPerSec: Double = 900.0
    private let maxImpulseFrames: Int = 2

    // State
    private var lastSpeed: Double?
    private var framesRemaining: Int = 0
    private var fired: Bool = false

    func reset() {
        lastSpeed = nil
        framesRemaining = 0
        fired = false
    }

    func arm() {
        framesRemaining = maxImpulseFrames
        fired = false
    }

    /// Returns true exactly once
    func update(speedPxPerSec: Double) -> Bool {
        defer { lastSpeed = speedPxPerSec }

        guard !fired,
              framesRemaining > 0,
              let prev = lastSpeed
        else {
            framesRemaining = max(framesRemaining - 1, 0)
            return false
        }

        let delta = speedPxPerSec - prev
        framesRemaining -= 1

        if delta >= minDeltaSpeedPxPerSec {
            fired = true
            return true
        }

        return false
    }
}
