//
//  MotionAnchorIntegrator.swift
//  LaunchLab
//
//  Motion Anchor + Integrator
//
//  Purpose:
//  Convert frame-to-frame jittery centers into a physically meaningful
//  motion signal by anchoring motion to a stable reference point and
//  integrating displacement over time.
//
//  This does NOT decide validity.
//  It produces a cleaner motion signal for MotionValidityGate.
//

import Foundation
import CoreGraphics

struct IntegratedMotion {
    let delta: CGVector          // integrated displacement
    let speedPxPerSec: Double    // magnitude / dt
    let direction: CGVector      // unit direction
}

final class MotionAnchorIntegrator {

    // MARK: - Parameters

    /// Number of frames to integrate over
    private let windowSize: Int = 3

    // MARK: - State

    private var anchor: CGPoint?
    private var samples: [(CGPoint, Double)] = []   // (center, timestamp)

    // MARK: - Reset

    func reset() {
        anchor = nil
        samples.removeAll()
    }

    // MARK: - Anchor

    func setAnchorIfNeeded(_ center: CGPoint?) {
        guard anchor == nil, let c = center else { return }
        anchor = c
    }

    // MARK: - Update

    func update(
        center: CGPoint?,
        timestampSec: Double
    ) -> IntegratedMotion? {

        guard let anchor, let c = center else { return nil }

        samples.append((c, timestampSec))

        if samples.count > windowSize {
            samples.removeFirst()
        }

        guard samples.count >= 2 else { return nil }

        let first = samples.first!
        let last  = samples.last!

        let dx = last.0.x - first.0.x
        let dy = last.0.y - first.0.y
        let dt = last.1 - first.1

        guard dt > 0 else { return nil }

        let delta = CGVector(dx: dx, dy: dy)
        let mag = hypot(dx, dy)

        guard mag > 0 else { return nil }

        let dir = CGVector(dx: dx / mag, dy: dy / mag)
        let speed = mag / dt

        return IntegratedMotion(
            delta: delta,
            speedPxPerSec: speed,
            direction: dir
        )
    }
}
