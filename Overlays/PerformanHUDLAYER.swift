//
//  PerformanceHUDLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import UIKit
import simd

final class PerformanceHUDLayer: CALayer {

    private var latestFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Public Update
    // ---------------------------------------------------------
    public func update(with frame: VisionFrameData) {
        self.latestFrame = frame
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        let w = bounds.width
        let origin = CGPoint(x: 8, y: 8)
        var y: CGFloat = origin.y

        // Common text style
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let color = UIColor.white

        func draw(_ text: String) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            text.draw(at: CGPoint(x: origin.x, y: y), withAttributes: attrs)
            y += 16
        }

        // ---------------------------------------------------------
        // 1. Frame Timing
        // ---------------------------------------------------------
        draw("FPS: \(FrameProfiler.shared.currentFPS)")
        draw("CPU total: \(String(format: "%.2f", FrameProfiler.shared.avg(for: "total_pipeline"))) ms")

        // Optional: show detector / tracker / LK times
        draw("Detector: \(String(format: \"%.2f\", FrameProfiler.shared.avg(for: \"detector\"))) ms")
        draw("Tracker:  \(String(format: \"%.2f\", FrameProfiler.shared.avg(for: \"tracker\"))) ms")
        draw("LK:       \(String(format: \"%.2f\", FrameProfiler.shared.avg(for: \"lk_refiner\"))) ms")
        draw("Velocity: \(String(format: \"%.2f\", FrameProfiler.shared.avg(for: \"velocity\"))) ms")
        draw("Pose:     \(String(format: \"%.2f\", FrameProfiler.shared.avg(for: \"pose\"))) ms")

        y += 8

        // ---------------------------------------------------------
        // 2. RS-PnP Angular Velocity Readout
        // ---------------------------------------------------------
        if let rs = frame.rspnp {

            // Angular velocity vector
            let wx = rs.w.x
            let wy = rs.w.y
            let wz = rs.w.z

            // Magnitude = rad/s
            let omegaMag = sqrt(wx*wx + wy*wy + wz*wz)

            // Convert rad/s → RPM
            let rpm = omegaMag * 60 / (2 * .pi)

            // Spin axis unit vector
            var spinAxis = SIMD3<Float>(0,0,0)
            if omegaMag > 1e-6 {
                spinAxis = normalize(rs.w)
            }

            draw("RS-PnP v1.5")
            draw("ω: [\(fmt(wx)), \(fmt(wy)), \(fmt(wz))] rad/s")
            draw("Spin Axis: [\(fmt(spinAxis.x)), \(fmt(spinAxis.y)), \(fmt(spinAxis.z))]")
            draw("RPM: \(fmt(rpm))")
            draw("RS Residual: \(fmt(rs.residual))")
        } else {
            draw("RS-PnP: (no solution)")
        }

        y += 8

        // ---------------------------------------------------------
        // 3. Intrinsics Debug
        // ---------------------------------------------------------
        let fx = frame.intrinsics.fx
        let fy = frame.intrinsics.fy
        draw("fx: \(fmt(fx))   fy: \(fmt(fy))")
    }
}

// -------------------------------------------------------------
// MARK: - Helpers
// -------------------------------------------------------------
private func fmt(_ v: Float) -> String {
    return String(format: "%.3f", v)
}