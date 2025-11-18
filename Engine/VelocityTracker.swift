//
//  VelocityTracker.swift
//  LaunchLab
//

import CoreGraphics
import simd

final class VelocityTracker {

    private var filters: [Int: KalmanFilter2D] = [:]
    private var lastTimestamp: CFTimeInterval?

    // ---------------------------------------------------------
    // MARK: - Velocity Gating
    // ---------------------------------------------------------
    private func gatedVelocity(_ v: CGVector) -> CGVector {
        let dx = v.dx, dy = v.dy

        if dx.isNaN || dy.isNaN || !dx.isFinite || !dy.isFinite {
            return .zero
        }
        let mag = sqrt(dx*dx + dy*dy)
        if mag <= 4 { return v }

        let scale = 4.0 / mag
        return CGVector(dx: dx * scale, dy: dy * scale)
    }

    // ---------------------------------------------------------
    // MARK: - Process
    // ---------------------------------------------------------
    func process(_ dots: [VisionDot], timestamp: CFTimeInterval) -> [VisionDot] {

        // Compute dt
        var dt: Float = 1.0 / 240.0
        if let last = lastTimestamp {
            let raw = timestamp - last
            if raw > 0.0005 && raw < 0.03 {
                dt = Float(raw)
            }
        }
        lastTimestamp = timestamp

        var out: [VisionDot] = []
        out.reserveCapacity(dots.count)

        for d in dots {

            // --------------------------------------------
            // Init or update KF
            // --------------------------------------------
            let pos = d.position

            let kf: KalmanFilter2D
            if let existing = filters[d.id] {
                kf = existing
                kf.predict(dt: dt)
                kf.update(measuredPos: pos)
            } else {
                kf = KalmanFilter2D(initialPos: pos)
                filters[d.id] = kf
            }

            // --------------------------------------------
            // Compute gated velocity + predicted
            // --------------------------------------------
            let rawV = kf.velocity
            let v = gatedVelocity(rawV)

            let predicted = CGPoint(
                x: pos.x + v.dx * CGFloat(dt),
                y: pos.y + v.dy * CGFloat(dt)
            )

            out.append(
                d.updating(predicted: predicted, velocity: v)
            )
        }

        // Prune filters for vanished dots
        let activeIDs = Set(out.map { $0.id })
        filters = filters.filter { activeIDs.contains($0.key) }

        return out
    }
}
