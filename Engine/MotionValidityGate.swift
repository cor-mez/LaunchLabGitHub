//
//  MotionValidityGate.swift
//  LaunchLab
//
//  Motion Validity Gate (V1.1)
//
//  Purpose:
//  Decide whether observed motion is physically plausible for a BALL,
//  versus camera jitter, lighting flicker, club-only motion,
//  or background texture movement.
//
//  This gate does NOT detect shots.
//  It only answers: “Is this motion real and ball-like?”
//
//  Runs AFTER PresenceAuthorityGate
//  Runs BEFORE ImpactSignatureLogger
//

import Foundation
import CoreGraphics

// MARK: - Decision

enum MotionValidityDecision: Equatable {
    case valid
    case invalid(reason: MotionInvalidReason)
}

// MARK: - Invalid Motion Classification

enum MotionInvalidReason: String, Equatable {
    case belowMinSpeed          = "below_min_speed"          // jitter / sensor noise
    case noMotionVector         = "no_motion_vector"         // missing velocity
    case insufficientHistory   = "insufficient_history"     // too few frames
    case directionFlipping     = "direction_flipping"       // sign reversals
    case directionIncoherent   = "direction_incoherent"     // unstable heading
    case noSpatialProgress     = "no_spatial_progress"      // vibration only
}

// MARK: - Gate

final class MotionValidityGate {

    // MARK: - Parameters (conservative, physics-first)

    /// Minimum speed to consider motion meaningful at all
    private let minSpeedPxPerSec: Double = 6.0

    /// Frames required with consistent direction
    private let minConsistentFrames: Int = 3

    /// Direction dot threshold for coherence
    private let minDirectionDot: Double = 0.35

    /// Maximum allowed direction reversals in window
    private let maxDirectionFlips: Int = 1

    /// Window size for motion analysis
    private let windowSize: Int = 5

    /// Minimum spatial displacement across window
    private let minSpatialDistancePx: Double = 3.0

    // MARK: - State

    private var recentDirections: [CGVector] = []
    private var recentCenters: [CGPoint] = []

    // MARK: - Reset

    func reset() {
        recentDirections.removeAll()
        recentCenters.removeAll()
    }

    // MARK: - Update

    func update(
        center: CGPoint?,
        velocityPx: CGVector?,
        speedPxPerSec: Double
    ) -> MotionValidityDecision {

        // --------------------------------------------------
        // Speed gate (reject jitter immediately)
        // --------------------------------------------------

        guard speedPxPerSec >= minSpeedPxPerSec else {
            reset()
            return .invalid(reason: .belowMinSpeed)
        }

        // --------------------------------------------------
        // Vector availability
        // --------------------------------------------------

        guard let center, let v = velocityPx else {
            reset()
            return .invalid(reason: .noMotionVector)
        }

        // --------------------------------------------------
        // Accumulate motion history
        // --------------------------------------------------

        let unitDir = normalize(v)
        recentDirections.append(unitDir)
        recentCenters.append(center)

        if recentDirections.count > windowSize {
            recentDirections.removeFirst()
            recentCenters.removeFirst()
        }

        // --------------------------------------------------
        // History sufficiency
        // --------------------------------------------------

        guard recentDirections.count >= minConsistentFrames else {
            return .invalid(reason: .insufficientHistory)
        }

        // --------------------------------------------------
        // Direction coherence analysis
        // --------------------------------------------------

        var flips = 0
        var coherentPairs = 0

        for i in 1..<recentDirections.count {
            let d0 = recentDirections[i - 1]
            let d1 = recentDirections[i]
            let dotVal = dot(d0, d1)

            if dotVal < 0 {
                flips += 1
            }

            if dotVal >= minDirectionDot {
                coherentPairs += 1
            }
        }

        if flips > maxDirectionFlips {
            return .invalid(reason: .directionFlipping)
        }

        if coherentPairs < (minConsistentFrames - 1) {
            return .invalid(reason: .directionIncoherent)
        }

        // --------------------------------------------------
        // Spatial accumulation (reject vibration)
        // --------------------------------------------------

        if let first = recentCenters.first,
           let last = recentCenters.last {

            let dx = last.x - first.x
            let dy = last.y - first.y
            let dist = hypot(dx, dy)

            if dist < minSpatialDistancePx {
                return .invalid(reason: .noSpatialProgress)
            }
        }

        // --------------------------------------------------
        // Motion is physically plausible
        // --------------------------------------------------

        return .valid
    }

    // MARK: - Helpers

    private func normalize(_ v: CGVector) -> CGVector {
        let mag = hypot(v.dx, v.dy)
        guard mag > 0 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }

    private func dot(_ a: CGVector, _ b: CGVector) -> Double {
        Double(a.dx * b.dx + a.dy * b.dy)
    }
}
