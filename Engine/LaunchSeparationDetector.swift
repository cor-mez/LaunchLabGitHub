//
//  LaunchSeparationDetector.swift
//  LaunchLab
//
//  Determines whether an observed impact transitioned into ballistic flight.
//  Observational only — does NOT grant authority.
//

import Foundation
import CoreGraphics

enum LaunchSeparationDecision {
    case separated
    case notSeparated(reason: Reason)

    enum Reason: String {
        case noImpact
        case insufficientVelocity
        case directionUnstable
        case noSpatialEscape
        case decayedImmediately
    }
}

final class LaunchSeparationDetector {

    // MARK: - Conservative observability thresholds (LOGGING ONLY)

    private let minSeparationSpeedPxPerSec: Double = 35.0
    private let minDirectionalConsistency: Double = 0.85
    private let minFramesPostImpact: Int = 3
    private let minSpatialEscapePx: Double = 6.0

    // MARK: - State

    private var impactOrigin: CGPoint?
    private var framesSinceImpact = 0
    private var lastDirection: CGVector?

    func reset() {
        impactOrigin = nil
        framesSinceImpact = 0
        lastDirection = nil
    }

    /// Observes whether ballistic separation emerges after an impact.
    /// NOTE: This detector does NOT consume internal impact event types.
    func update(
        impactObserved: Bool,
        impactCenter: CGPoint?,
        center: CGPoint?,
        velocityPx: CGVector?,
        speedPxPerSec: Double
    ) -> LaunchSeparationDecision {

        guard impactObserved else {
            return .notSeparated(reason: .noImpact)
        }

        guard speedPxPerSec >= minSeparationSpeedPxPerSec else {
            return .notSeparated(reason: .insufficientVelocity)
        }

        guard let center, let v = velocityPx else {
            return .notSeparated(reason: .noSpatialEscape)
        }

        // Establish impact origin once
        if impactOrigin == nil {
            impactOrigin = impactCenter ?? center
            lastDirection = normalize(v)
            framesSinceImpact = 0
            return .notSeparated(reason: .noSpatialEscape)
        }

        framesSinceImpact += 1

        guard framesSinceImpact >= minFramesPostImpact else {
            return .notSeparated(reason: .noSpatialEscape)
        }

        guard let dir = normalize(v) else {
            return .notSeparated(reason: .directionUnstable)
        }

        if let last = lastDirection {
            let dot = (dir.dx * last.dx) + (dir.dy * last.dy)
            if dot < minDirectionalConsistency {
                return .notSeparated(reason: .directionUnstable)
            }
        }

        let dx = center.x - impactOrigin!.x
        let dy = center.y - impactOrigin!.y
        let dist = hypot(dx, dy)

        guard dist >= minSpatialEscapePx else {
            return .notSeparated(reason: .noSpatialEscape)
        }

        lastDirection = dir
        return .separated
    }

    // MARK: - Helpers

    private func normalize(_ v: CGVector) -> CGVector? {
        let mag = sqrt(v.dx * v.dx + v.dy * v.dy)
        guard mag > 1e-6 else { return nil }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }
}
