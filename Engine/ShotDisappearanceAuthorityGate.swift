//
//  ShotDisappearanceAuthorityGate.swift
//  LaunchLab
//
//  Authorizes a shot based on impact + disappearance.
//  This is the PRIMARY authority on mobile cameras.
//

import Foundation
import CoreGraphics

final class ShotDisappearanceAuthorityGate {

    // MARK: - Parameters (conservative V1)

    /// Frames after impact in which disappearance must occur
    private let maxFramesAfterImpact: Int = 4

    /// Require the ball to have been present immediately before impact
    private let requirePreImpactPresence: Bool = true

    // MARK: - State

    private var armed: Bool = false
    private var framesSinceImpact: Int = 0
    private var fired: Bool = false

    // MARK: - Lifecycle

    func reset() {
        armed = false
        framesSinceImpact = 0
        fired = false
    }

    /// Arm on confirmed impact signature
    func arm() {
        armed = true
        framesSinceImpact = 0
        fired = false
        Log.info(.shot, "[DISAPPEAR] armed")
    }

    /// Call once per frame while armed
    func advanceFrame() {
        guard armed else { return }
        framesSinceImpact += 1
    }

    /// Evaluate disappearance.
    /// Returns true exactly once when authorized.
    func evaluate(
        ballPresent: Bool,
        cameraStable: Bool
    ) -> Bool {

        guard armed, !fired else { return false }

        // Camera instability veto (truth-preserving)
        guard cameraStable else {
            Log.info(.shot, "[DISAPPEAR] veto camera_unstable")
            reset()
            return false
        }

        // Ball disappears shortly after impact → AUTHORIZE
        if !ballPresent {
            fired = true
            Log.info(
                .shot,
                "[SHOT] authorized_by_disappearance frames=\(framesSinceImpact)"
            )
            return true
        }

        // Expired window → refuse
        if framesSinceImpact > maxFramesAfterImpact {
            Log.info(
                .shot,
                "[DISAPPEAR] expired frames=\(framesSinceImpact)"
            )
            reset()
        }

        return false
    }
}
