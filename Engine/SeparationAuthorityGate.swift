//
//  SeparationAuthorityGate.swift
//  LaunchLab
//
//  Authoritative confirmation of ballistic flight.
//  THIS is the only gate allowed to authorize a shot.
//

import Foundation
import CoreGraphics

final class SeparationAuthorityGate {

    // MARK: - Conservative V1 thresholds

    private let minFrames: Int = 3
    private let minSpeedPxPerSec: Double = 30.0
    private let minEscapePx: Double = 6.0
    private let maxDirectionFlipDot: Double = 0.6

    // MARK: - State

    private var frames: Int = 0
    private var origin: CGPoint?
    private var lastDir: CGVector?
    private var fired: Bool = false

    // MARK: - Reset

    func reset() {
        frames = 0
        origin = nil
        lastDir = nil
        fired = false
    }

    // MARK: - Update

    /// Returns true exactly once when separation is authoritative
    func update(
        center: CGPoint,
        velocityPx: CGVector,
        speedPxPerSec: Double,
        cameraStable: Bool
    ) -> Bool {

        guard !fired else { return false }

        // Camera instability veto (hint, not authority)
        guard cameraStable else {
            reset()
            return false
        }

        guard speedPxPerSec >= minSpeedPxPerSec else {
            reset()
            return false
        }

        let dir = normalize(velocityPx)

        if origin == nil {
            origin = center
            lastDir = dir
            frames = 1
            return false
        }

        frames += 1

        if let last = lastDir {
            let dot = (dir.dx * last.dx) + (dir.dy * last.dy)
            if dot < maxDirectionFlipDot {
                reset()
                return false
            }
        }

        let dx = center.x - origin!.x
        let dy = center.y - origin!.y
        let dist = hypot(dx, dy)

        guard dist >= minEscapePx else {
            return false
        }

        lastDir = dir

        guard frames >= minFrames else {
            return false
        }

        fired = true
        Log.info(.shot, "[SEPARATION] authoritative")
        return true
    }

    // MARK: - Helpers

    private func normalize(_ v: CGVector) -> CGVector {
        let mag = hypot(v.dx, v.dy)
        guard mag > 1e-6 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }
}
