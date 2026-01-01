//
//  PresenceContinuityLatch.swift
//  LaunchLab
//
//  Purpose:
//  Maintain object continuity across impact when presence
//  becomes unobservable due to physics (impulse, RS shear, blur).
//
//  This is NOT authority.
//  This does NOT detect shots.
//  It only answers: "should we treat the next frames as belonging
//  to the same physical object?"
//

import Foundation

final class PresenceContinuityLatch {

    // MARK: - Configuration (OBSERVATIONAL)

    /// Frames of confirmed presence required to arm latch
    private let minPresenceFrames: Int = 4

    /// Max frames latch may remain active after impact
    private let maxLatchedFrames: Int = 10

    // MARK: - State

    private var presenceFrames: Int = 0
    private var latchedFramesRemaining: Int = 0
    private var latched: Bool = false

    // MARK: - Public API

    func reset() {
        presenceFrames = 0
        latchedFramesRemaining = 0
        latched = false
    }

    /// Call once per frame when presence is confirmed
    func observePresence(present: Bool) {
        if present {
            presenceFrames += 1
        } else {
            presenceFrames = 0
        }
    }

    /// Arms latch if sufficient presence history exists
    func canArm() -> Bool {
        return presenceFrames >= minPresenceFrames
    }

    /// Triggered by an impact signature
    func latch() {
        guard canArm() else { return }
        latched = true
        latchedFramesRemaining = maxLatchedFrames

        Log.info(.shot, "PHASE presence_latched frames=\(maxLatchedFrames)")
    }

    /// Call every frame post-impact
    func tick() {
        guard latched else { return }

        latchedFramesRemaining -= 1
        if latchedFramesRemaining <= 0 {
            reset()
            Log.info(.shot, "PHASE presence_latch_expired")
        }
    }

    /// Whether continuity should be assumed this frame
    var isActive: Bool {
        return latched
    }
}
