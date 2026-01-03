//
//  MotionValidityGate.swift
//  LaunchLab
//
//  Judges ballistic motion ONLY.
//

import CoreGraphics

enum MotionValidityDecision {
    case valid
    case invalid(reason: String)
    case bypassed
}

final class MotionValidityGate {

    private let minSpeedPxPerSec: Double = 6.0
    private let minConsistentFrames: Int = 3
    private let minDirectionDot: Double = 0.35
    private let maxDirectionFlips: Int = 1
    private let windowSize: Int = 5
    private let minSpatialDistancePx: Double = 3.0

    private var recentDirections: [CGVector] = []
    private var recentCenters: [CGPoint] = []

    func reset() {
        recentDirections.removeAll()
        recentCenters.removeAll()
    }

    func update(
        phase: MotionPhase,
        center: CGPoint,
        velocityPx: CGVector,
        speedPxPerSec: Double
    ) -> MotionValidityDecision {

        // 🚫 NEVER judge during impact
        guard phase == .separation else {
            return .bypassed
        }

        guard speedPxPerSec >= minSpeedPxPerSec else {
            reset()
            return .invalid(reason: "below_min_speed")
        }

        let mag = hypot(velocityPx.dx, velocityPx.dy)
        guard mag > 0 else {
            reset()
            return .invalid(reason: "no_motion_vector")
        }

        let dir = CGVector(dx: velocityPx.dx / mag, dy: velocityPx.dy / mag)

        recentDirections.append(dir)
        recentCenters.append(center)

        if recentDirections.count > windowSize {
            recentDirections.removeFirst()
            recentCenters.removeFirst()
        }

        guard recentDirections.count >= minConsistentFrames else {
            return .invalid(reason: "insufficient_history")
        }

        var flips = 0
        var coherent = 0

        for i in 1..<recentDirections.count {
            let d0 = recentDirections[i - 1]
            let d1 = recentDirections[i]
            let dot = d0.dx * d1.dx + d0.dy * d1.dy

            if dot < 0 { flips += 1 }
            if dot >= minDirectionDot { coherent += 1 }
        }

        if flips > maxDirectionFlips {
            return .invalid(reason: "direction_flipping")
        }

        if coherent < minConsistentFrames - 1 {
            return .invalid(reason: "direction_incoherent")
        }

        if let first = recentCenters.first,
           let last = recentCenters.last {

            let dist = hypot(last.x - first.x, last.y - first.y)
            if dist < minSpatialDistancePx {
                return .invalid(reason: "no_spatial_progress")
            }
        }

        return .valid
    }
}
