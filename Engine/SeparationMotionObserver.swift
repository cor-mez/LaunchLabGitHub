//
//  SeparationMotionObserver.swift
//  LaunchLab
//
//  Observes whether motion remains coherent after impact
//  inside a directional attention ROI.
//

import CoreGraphics
import Foundation

enum SeparationObservation {
    case none
    case chaotic(reason: String)
    case coherent(frameCount: Int)
}

final class SeparationMotionObserver {

    private var framesObserved = 0
    private var lastCenter: CGPoint?

    func reset() {
        framesObserved = 0
        lastCenter = nil
    }

    func observe(
        center: CGPoint?,
        velocityPx: CGVector?,
        expectedDirection: CGVector
    ) -> SeparationObservation {

        guard let center, let v = velocityPx else {
            return .none
        }

        let mag = hypot(v.dx, v.dy)
        guard mag > 1e-6 else {
            return .chaotic(reason: "velocity_zero")
        }

        let ux = v.dx / mag
        let uy = v.dy / mag

        let dot = (ux * expectedDirection.dx) + (uy * expectedDirection.dy)
        if dot < 0.7 {
            return .chaotic(reason: "direction_diverged")
        }

        if let last = lastCenter {
            let dx = center.x - last.x
            let dy = center.y - last.y
            let dist = hypot(dx, dy)
            if dist < 2 {
                return .chaotic(reason: "no_spatial_progress")
            }
        }

        lastCenter = center
        framesObserved += 1

        return .coherent(frameCount: framesObserved)
    }
}
