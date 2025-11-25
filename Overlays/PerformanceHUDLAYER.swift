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

    // Simple FPS estimator (FrameProfiler does NOT contain one)
    private var lastTime: CFTimeInterval = CACurrentMediaTime()
    private var fps: Double = 0

    // ---------------------------------------------------------
    // MARK: - Public Update
    // ---------------------------------------------------------
    public func update(with frame: VisionFrameData) {
        self.latestFrame = frame
        updateFPS()
        setNeedsDisplay()
    }

    private func updateFPS() {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now

        // exponential smoothing
        let alpha = 0.1
        let instant = 1.0 / max(dt, 0.0001)
        fps = alpha * instant + (1 - alpha) * fps
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        let origin = CGPoint(x: 8, y: 8)
        var y: CGFloat = origin.y

        // Text Style
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
        // 1. FPS (local estimate)
        // ---------------------------------------------------------
        draw(String(format: "FPS: %.1f", fps))

        // ---------------------------------------------------------
        // 2. Pipeline Profiling (FrameProfiler)
        // ---------------------------------------------------------
        let m = FrameProfiler.shared.visualMetrics()
        draw("Total:    \(m.total) ms")
        draw("Detector: \(m.detector) ms")
        draw("Tracker:  \(m.tracker) ms")
        draw("LK:       \(m.lk) ms")
        draw("Velocity: \(m.velocity) ms")
        draw("Pose:     \(m.pose) ms")

        y += 8

        // GPU (if present)
        draw("GPU last: \(m.gpuLast) ms")
        draw("GPU avg:  \(m.gpuAvg) ms")

        y += 8

        // ---------------------------------------------------------
        // 3. RS-PnP Debug
        // ---------------------------------------------------------
        if let rs = frame.rspnp {

            let w = rs.w
            let omegaMag = sqrt(w.x*w.x + w.y*w.y + w.z*w.z)
            let rpm = omegaMag * 60 / (2 * .pi)

            draw("RS-PnP v1.5")
            draw("ω: [\(fmt(w.x)), \(fmt(w.y)), \(fmt(w.z))] rad/s")
            draw("Spin Axis: [\(fmt(normalizeSafe(w).x)), \(fmt(normalizeSafe(w).y)), \(fmt(normalizeSafe(w).z))]")
            draw("RPM: \(fmt(rpm))")
            draw("Residual: \(fmt(rs.residual))")
        } else {
            draw("RS-PnP: (no solution)")
        }

        y += 8

        // ---------------------------------------------------------
        // 4. Intrinsics Debug
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

private func fmt(_ v: Double) -> String {
    return String(format: "%.3f", v)
}

private func normalizeSafe(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let m = simd_length(v)
    return m > 1e-6 ? v / m : SIMD3<Float>(0,0,0)
}
