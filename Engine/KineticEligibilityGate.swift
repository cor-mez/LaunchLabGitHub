//
//  KineticEligibilityGate.swift
//  LaunchLab
//
//  Observational-only gate.
//  Answers ONE question:
//
//  "Is the current motion regime energetic enough
//   that separation could physically exist?"
//
//  This gate does NOT:
//  - detect shots
//  - authorize shots
//  - suppress impact signatures
//
//  It only permits *separation observability*.
//

import Foundation
import CoreGraphics

final class KineticEligibilityGate {

    // MARK: - Constants (physics envelope, not tuning)

    /// Ignore micro-motion below this (camera noise, lighting shimmer)
    private let minSustainedSpeedPxPerSec: Double = 18.0

    /// Frames that speed must remain above threshold
    private let requiredFrames: Int = 3

    /// Direction must not wildly diverge across frames
    private let minDirectionDot: Double = 0.6

    // MARK: - State

    private var activeFrameCount: Int = 0
    private var lastDirection: CGVector?

    var isEligible: Bool {
        activeFrameCount >= requiredFrames
    }

    // MARK: - Lifecycle

    func reset() {
        activeFrameCount = 0
        lastDirection = nil
    }

    // MARK: - Update

    func observe(
        speedPxPerSec: Double,
        velocityPx: CGVector?
    ) {

        guard speedPxPerSec >= minSustainedSpeedPxPerSec,
              let v = velocityPx,
              let dir = unit(v) else {

            reset()
            return
        }

        if let last = lastDirection {
            let dot = (dir.dx * last.dx) + (dir.dy * last.dy)
            if dot < minDirectionDot {
                reset()
                return
            }
        }

        activeFrameCount += 1
        lastDirection = dir
    }

    // MARK: - Vector Math

    private func unit(_ v: CGVector) -> CGVector? {
        let mag = hypot(Double(v.dx), Double(v.dy))
        guard mag > 1e-6 else { return nil }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }
}
