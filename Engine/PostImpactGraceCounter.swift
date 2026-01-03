//
//  PostImpactGraceCounter.swift
//  LaunchLab
//
//  Allows brief post-impact observability loss
//  WITHOUT granting authority.
//
//  Purpose:
//  - Handle high-speed launch where ball exits ROI in ≤1 frame
//  - Preserve refusal-first integrity
//

import Foundation
import CoreGraphics

final class PostImpactGraceCounter {

    // MARK: - Configuration (tight, physics-aware)

    /// Max frames allowed without seeing the ball post-impact
    private let maxGraceFrames: Int = 2

    /// Minimum inferred speed to consider escape plausible
    private let minEscapeSpeedPxPerSec: Double = 35.0

    // MARK: - State

    private var active: Bool = false
    private var remainingFrames: Int = 0

    private var lastKnownCenter: CGPoint?
    private var lastKnownVelocity: CGVector?

    // MARK: - Lifecycle

    func reset() {
        active = false
        remainingFrames = 0
        lastKnownCenter = nil
        lastKnownVelocity = nil
    }

    /// Arm immediately when impact is observed
    func arm(center: CGPoint, velocity: CGVector) {
        active = true
        remainingFrames = maxGraceFrames
        lastKnownCenter = center
        lastKnownVelocity = velocity
    }

    /// Call when ball is NOT observed post-impact
    /// Returns true if grace still valid
    func consumeMissingFrame() -> Bool {
        guard active else { return false }

        remainingFrames -= 1
        if remainingFrames < 0 {
            reset()
            return false
        }

        return true
    }

    /// Call when ball reappears
    /// Determines whether separation is explainable
    func validateReappearance(
        center: CGPoint,
        speedPxPerSec: Double
    ) -> Bool {

        guard
            active,
            let lastCenter = lastKnownCenter,
            let lastVelocity = lastKnownVelocity
        else {
            reset()
            return false
        }

        // Require real escape energy
        guard speedPxPerSec >= minEscapeSpeedPxPerSec else {
            reset()
            return false
        }

        // Directional plausibility (loose)
        let dx = center.x - lastCenter.x
        let dy = center.y - lastCenter.y
        let escapeVec = CGVector(dx: dx, dy: dy)

        let dot =
            (escapeVec.dx * lastVelocity.dx) +
            (escapeVec.dy * lastVelocity.dy)

        if dot <= 0 {
            reset()
            return false
        }

        // Explainable separation
        reset()
        return true
    }
}
