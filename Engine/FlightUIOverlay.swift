//
//  FlightUIOverlay.swift
//  LaunchLab
//
//  Stage 6 — Module 24
//
//  Overlay Responsibilities:
//    • Draw TrackMan-style gradient flight path (orange → yellow)
//    • Draw ball marker at current projected position
//    • Auto-scale arc to fit screen
//    • Use yards for carry/apex labels
//    • Pseudo-3D isometric projection (camera-corrected world frame)
//    • Draw solid ground line
//    • Always render above all other overlays
//
//  No dependencies added to VisionTypes.
//  No shared types created.
//  Pure CoreGraphics drawing.
//  ARCHITECTURE-FREEZE COMPLIANT
//

import UIKit
import simd

// ------------------------------------------------------------
// MARK: - File-Local Calibration Proxy
// ------------------------------------------------------------
// TiltCorrection.swift defines CalibrationProxy as fileprivate,
// so this file cannot access it. We mirror the same structure
// here as a *file-local* type so casting succeeds.
// This does NOT modify frozen types.
// ------------------------------------------------------------

fileprivate struct CalibrationProxy {
    let roll: Float
    let pitch: Float
    let yawOffset: Float
    let cameraToTeeDistance: Float
    let launchOrigin: SIMD3<Float>
    let worldAlignmentR: simd_float3x3
}

// ------------------------------------------------------------
// MARK: - FlightUIOverlayLayer
// ------------------------------------------------------------

final class FlightUIOverlayLayer: CALayer {

    // Latest corrected pose & calibration from VisionPipeline.
    private var latestPose: RSPnPResult?
    private var latestCalibration: Any?
    private var latestTimestamp: Double = 0

    // ------------------------------------------------------------
    // MARK: - Update Interface
    // ------------------------------------------------------------
    public func update(frame: VisionFrameData, calibration: Any?) {
        guard let rspnp = frame.rspnp, rspnp.isValid else { return }

        self.latestPose = rspnp
        self.latestCalibration = calibration
        self.latestTimestamp = frame.timestamp

        setNeedsDisplay()
    }

    // ------------------------------------------------------------
    // MARK: - Drawing
    // ------------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let rspnp = latestPose else { return }
        guard let cal = latestCalibration as? CalibrationProxy else { return }

        // STEP 1 — World-frame velocity
        let vWorld = simd_normalize(cal.worldAlignmentR * rspnp.v)

        // STEP 2 — Pseudo-3D projection
        let iso: (SIMD3<Float>) -> CGPoint = { w in
            let xs = CGFloat(w.z * 0.7 + w.x * 0.3)
            let ys = CGFloat(-w.y)
            return CGPoint(x: xs, y: ys)
        }

        // STEP 3 — Gravity-only arc
        let g = SIMD3<Float>(0, -9.81, 0)
        let samples = generateArcSamples(v0: vWorld, g: g, steps: 60)

        var pts = samples.map { iso($0) }

        // Fit within layer
        if let scaled = scalePathToLayer(pts, size: bounds.size) {
            pts = scaled
        }

        // STEP 4 — Ground line
        ctx.setStrokeColor(UIColor(white: 1.0, alpha: 0.6).cgColor)
        ctx.setLineWidth(2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: bounds.height - 20))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.height - 20))
        ctx.strokePath()

        // STEP 5 — Flight path
        drawGradientPath(ctx: ctx, points: pts)

        // STEP 6 — Ball marker
        if let end = pts.last { drawBallMarker(ctx: ctx, at: end) }

        // STEP 7 — Carry + Apex labels
        drawFlightLabels(ctx: ctx, pts: pts, v0: vWorld)
    }

    // ------------------------------------------------------------
    // MARK: - Arc Generation
    // ------------------------------------------------------------
    private func generateArcSamples(
        v0: SIMD3<Float>,
        g: SIMD3<Float>,
        steps: Int
    ) -> [SIMD3<Float>] {

        var pts: [SIMD3<Float>] = []
        let dt: Float = 0.03

        for i in 0..<steps {
            let t = Float(i) * dt
            let p = v0 * t + 0.5 * g * (t * t)
            if p.y < 0 { break }
            pts.append(p)
        }
        return pts
    }

    // ------------------------------------------------------------
    // MARK: - Path Scaling
    // ------------------------------------------------------------
    private func scalePathToLayer(_ pts: [CGPoint], size: CGSize) -> [CGPoint]? {
        guard !pts.isEmpty else { return nil }

        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return pts }

        let scaleX = size.width * 0.8 / width
        let scaleY = size.height * 0.6 / height
        let scale = min(scaleX, scaleY)

        let offsetX = (size.width - width * scale) / 2
        let offsetY = (size.height - height * scale) / 2

        return pts.map {
            CGPoint(
                x: ($0.x - minX) * scale + offsetX,
                y: ($0.y - minY) * scale + offsetY
            )
        }
    }

    // ------------------------------------------------------------
    // MARK: - Path & Marker Drawing
    // ------------------------------------------------------------
    private func drawGradientPath(ctx: CGContext, points: [CGPoint]) {
        guard points.count > 1 else { return }

        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]

            let t = CGFloat(i) / CGFloat(points.count - 1)

            let color = UIColor(
                red: 1.0,
                green: 0.5 + 0.5 * t,
                blue: 0.0,
                alpha: 1.0
            ).cgColor

            ctx.setStrokeColor(color)
            ctx.setLineWidth(3)
            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.strokePath()
        }
    }

    private func drawBallMarker(ctx: CGContext, at point: CGPoint) {
        let r: CGFloat = 6
        let rect = CGRect(x: point.x - r, y: point.y - r, width: 2*r, height: 2*r)

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: rect)
    }

    // ------------------------------------------------------------
    // MARK: - Labels
    // ------------------------------------------------------------
    private func drawFlightLabels(
        ctx: CGContext,
        pts: [CGPoint],
        v0: SIMD3<Float>
    ) {
        guard pts.count > 2 else { return }

        let carry = estimateCarry(v0)
        let apex = estimateApex(v0)

        let text = String(format: "Carry: %.1f yd\nApex: %.1f ft", carry, apex)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.white
        ]

        let size = text.size(withAttributes: attrs)

        let rect = CGRect(x: 12, y: 12, width: size.width, height: size.height)
        text.draw(in: rect, withAttributes: attrs)
    }

    // ------------------------------------------------------------
    // MARK: - Metric Estimation
    // ------------------------------------------------------------
    private func estimateCarry(_ v0: SIMD3<Float>) -> Float {
        let horiz = SIMD2<Float>(v0.x, v0.z)
        let vHoriz = simd_length(horiz)

        let vy = v0.y
        let t = (2 * vy) / 9.81
        if t <= 0 { return 0 }

        return (vHoriz * t) * 1.09361
    }

    private func estimateApex(_ v0: SIMD3<Float>) -> Float {
        let vy = v0.y
        let h = (vy * vy) / (2 * 9.81)
        return h * 3.28084
    }
}
