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
    // MARK: - Update
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

        let origin = CGPoint(x: 8, y: 8)
        var y: CGFloat = origin.y

        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let color = UIColor.white

        func drawLine(_ text: String) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            text.draw(at: CGPoint(x: origin.x, y: y), withAttributes: attrs)
            y += 16
        }

        let profiler = FrameProfiler.shared

        // ---------------------------------------------------------
        // 1. FRAME TIMING
        // ---------------------------------------------------------
        drawLine("FPS: \(profiler.fps)")
        drawLine("CPU total: \(fmt(profiler.averageMS("total_pipeline"))) ms")
        drawLine("Detector:  \(fmt(profiler.averageMS("detector"))) ms")
        drawLine("Tracker:   \(fmt(profiler.averageMS("tracker"))) ms")
        drawLine("LK:        \(fmt(profiler.averageMS("lk_refiner"))) ms")
        drawLine("Velocity:  \(fmt(profiler.averageMS("velocity"))) ms")
        drawLine("Pose:      \(fmt(profiler.averageMS("pose"))) ms")

        y += 8

        // ---------------------------------------------------------
        // 2. RS-PnP READOUT
        // ---------------------------------------------------------
        if let rs = frame.rspnp {
            let w = rs.w
            let omegaMag = simd_length(w)
            let rpm = omegaMag * 60.0 / (2.0 * .pi)

            let spinAxis: SIMD3<Float> = omegaMag > 1e-6 ? normalize(w) : SIMD3(0,0,0)

            drawLine("RS-PnP v1.5")
            drawLine("ω: [\(fmt(w.x)), \(fmt(w.y)), \(fmt(w.z))] rad/s")
            drawLine("Axis: [\(fmt(spinAxis.x)), \(fmt(spinAxis.y)), \(fmt(spinAxis.z))]")
            drawLine("RPM: \(fmt(rpm))")
            drawLine("Residual: \(fmt(rs.residual))")
        } else {
            drawLine("RS-PnP: (no solution)")
        }

        y += 8

        // ---------------------------------------------------------
        // 3. INTRINSICS
        // ---------------------------------------------------------
        drawLine("fx: \(fmt(frame.intrinsics.fx))   fy: \(fmt(frame.intrinsics.fy))")
    }
}

// -------------------------------------------------------------
// MARK: - Formatter
// -------------------------------------------------------------
private func fmt(_ v: Float) -> String {
    String(format: "%.3f", v)
}
