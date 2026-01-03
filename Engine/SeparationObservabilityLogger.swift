//
//  SeparationObservabilityLogger.swift
//  LaunchLab
//
//  LOG-ONLY observability for separation failure analysis.
//  Does NOT grant authority. Does NOT gate anything.
//

import Foundation
import CoreGraphics

final class SeparationObservabilityLogger {

    struct Snapshot {
        var framesVisible: Int = 0
        var maxSpeedPxPerSec: Double = 0
        var maxEscapePx: Double = 0
        var directionFlips: Int = 0
        var cameraUnstable: Bool = false
        var ballLost: Bool = false
    }

    private var origin: CGPoint?
    private var lastDir: CGVector?
    private var snapshot = Snapshot()

    // MARK: - Reset

    func reset() {
        origin = nil
        lastDir = nil
        snapshot = Snapshot()
    }

    // MARK: - Observe (call every post-impact frame)

    func observe(
        center: CGPoint?,
        velocityPx: CGVector?,
        speedPxPerSec: Double,
        cameraStable: Bool
    ) {
        snapshot.framesVisible += 1

        snapshot.maxSpeedPxPerSec = max(
            snapshot.maxSpeedPxPerSec,
            speedPxPerSec
        )

        if !cameraStable {
            snapshot.cameraUnstable = true
        }

        guard let center, let velocityPx else {
            snapshot.ballLost = true
            return
        }

        if origin == nil {
            origin = center
            lastDir = normalize(velocityPx)
            return
        }

        let dx = center.x - origin!.x
        let dy = center.y - origin!.y
        let dist = hypot(dx, dy)
        snapshot.maxEscapePx = max(snapshot.maxEscapePx, dist)

        let dir = normalize(velocityPx)
        if let last = lastDir {
            let dot = (dir.dx * last.dx) + (dir.dy * last.dy)
            if dot < 0.6 {
                snapshot.directionFlips += 1
            }
        }

        lastDir = dir
    }

    // MARK: - Emit summary (call once when shot attempt ends)

    func emitSummary() {
        var reasons: [String] = []

        if snapshot.ballLost {
            reasons.append("ball_lost_early")
        }
        if snapshot.maxEscapePx < 6 {
            reasons.append("insufficient_escape")
        }
        if snapshot.maxSpeedPxPerSec < 30 {
            reasons.append("insufficient_speed")
        }
        if snapshot.directionFlips > 0 {
            reasons.append("direction_unstable")
        }
        if snapshot.cameraUnstable {
            reasons.append("camera_unstable")
        }

        let reasonStr = reasons.isEmpty ? "unknown" : reasons.joined(separator: ",")

        Log.info(
            .shot,
            "[SEPARATION_OBS] " +
            "frames=\(snapshot.framesVisible) " +
            "max_px_s=\(fmt1(snapshot.maxSpeedPxPerSec)) " +
            "max_escape=\(fmt1(snapshot.maxEscapePx)) " +
            "dir_flips=\(snapshot.directionFlips) " +
            "reason=\(reasonStr)"
        )
    }

    // MARK: - Helpers

    private func normalize(_ v: CGVector) -> CGVector {
        let mag = hypot(v.dx, v.dy)
        guard mag > 1e-6 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}
