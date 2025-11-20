//
//  SpinDriftOverlayLayer.swift
//  LaunchLab
//

import UIKit
import simd
import CoreGraphics

// ============================================================
// MARK: - Spin Drift Debug Overlay (Zero-Alloc Draw)
// ============================================================

final class SpinDriftOverlayLayer: CALayer {

    // --------------------------------------------------------
    // MARK: - Public Inputs (set by PreviewContainerView)
// --------------------------------------------------------
    public var mapper: VisionOverlaySupport?
    public var spinDrift: SpinDriftMetrics = .zero
    public var spin: SpinResult?
    public var prevSpin: SpinResult?        // supplied by container

    // --------------------------------------------------------
    // MARK: - Cached State (used only during draw)
// --------------------------------------------------------
    private var axisCurr = SIMD3<Float>(0,0,0)
    private var axisPrev = SIMD3<Float>(0,0,0)

    private var driftDeg: Float = 0
    private var omegaDiff: Float = 0
    private var stability: Float = 0
    private var wobble: Bool = false

    private var prevValid = false
    private var hasData = false

    private var centerPx: CGPoint = .zero

    // ============================================================
    // MARK: - UPDATE
    // ============================================================
    func updateFrame(_ frame: VisionFrameData, size: CGSize) {

        guard let spin = frame.spin else {
            hasData = false
            setNeedsDisplay()
            return
        }

        // --- Current axis ---
        axisCurr = spin.axis

        // --- Metrics ---
        driftDeg  = frame.spinDrift.axisDriftDeg
        omegaDiff = frame.spinDrift.omegaDrift
        stability = frame.spinDrift.stabilityScore
        wobble    = frame.spinDrift.wobbleFlag

        // --- Previous axis (provided by container each frame) ---
        if let prev = prevSpin {
            axisPrev  = prev.axis
            prevValid = true
        } else {
            axisPrev  = axisCurr
            prevValid = false
        }

        centerPx = CGPoint(x: bounds.midX, y: bounds.midY)
        hasData = true

        setNeedsDisplay()
    }

    // ============================================================
    // MARK: - DRAW
    // ============================================================
    override func draw(in ctx: CGContext) {
        guard hasData else { return }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setLineWidth(2.0)

        // --------------------------------------------------------
        // 1. Current axis arrow
        // --------------------------------------------------------
        let currColor = colorForDrift(driftDeg)
        ctx.setStrokeColor(currColor.cgColor)

        let currEnd = projectAxis(axisCurr)
        ctx.move(to: centerPx)
        ctx.addLine(to: currEnd)
        ctx.strokePath()

        drawArrowHead(ctx, from: centerPx, to: currEnd, color: currColor)

        // --------------------------------------------------------
        // 2. Previous axis (ghosted)
        // --------------------------------------------------------
        if prevValid {
            let prevColor = UIColor(white: 1.0, alpha: 0.25)
            ctx.setStrokeColor(prevColor.cgColor)

            let prevEnd = projectAxis(axisPrev)
            ctx.move(to: centerPx)
            ctx.addLine(to: prevEnd)
            ctx.strokePath()
        }

        // --------------------------------------------------------
        // 3. Drift vector (prev → curr)
        // --------------------------------------------------------
        if prevValid {
            let prevEnd = projectAxis(axisPrev)
            let currEnd = projectAxis(axisCurr)

            ctx.setStrokeColor(UIColor.systemOrange.cgColor)
            ctx.move(to: prevEnd)
            ctx.addLine(to: currEnd)
            ctx.strokePath()
        }

        // --------------------------------------------------------
        // 4. HUD
        // --------------------------------------------------------
        drawHUD(ctx)
    }

    // ============================================================
    // MARK: - PROJECT AXIS → SCREEN
    // ============================================================
    @inline(__always)
    private func projectAxis(_ axis: SIMD3<Float>) -> CGPoint {
        let scale = min(bounds.width, bounds.height) * 0.25
        let x = CGFloat(axis.x) * scale
        let y = CGFloat(-axis.y) * scale
        return CGPoint(x: centerPx.x + x, y: centerPx.y + y)
    }

    // ============================================================
    // MARK: - DRAW ARROW HEAD
    // ============================================================
    @inline(__always)
    private func drawArrowHead(
        _ ctx: CGContext,
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let L  = CGFloat(hypot(dx, dy))
        if L < 4 { return }

        let ux = dx / L
        let uy = dy / L

        let size: CGFloat = 12

        let w1 = CGPoint(
            x: end.x - ux*size - uy*(size*0.5),
            y: end.y - uy*size + ux*(size*0.5)
        )
        let w2 = CGPoint(
            x: end.x - ux*size + uy*(size*0.5),
            y: end.y - uy*size - ux*(size*0.5)
        )

        ctx.setStrokeColor(color.cgColor)
        ctx.move(to: end); ctx.addLine(to: w1); ctx.strokePath()
        ctx.move(to: end); ctx.addLine(to: w2); ctx.strokePath()
    }

    // ============================================================
    // MARK: - COLOR CODING
    // ============================================================
    @inline(__always)
    private func colorForDrift(_ d: Float) -> UIColor {
        if d < 2 { return .systemGreen }
        if d < 5 { return .systemYellow }
        return .systemRed
    }

    // ============================================================
    // MARK: - HUD
    // ============================================================
    private func drawHUD(_ ctx: CGContext) {

        let wobbleText = wobble ? "YES" : "NO"

        let info = String(
            format: "Drift: %.2f°\nΔ|ω|: %.2f\nStability: %.2f\nWobble: %@",
            driftDeg,
            omegaDiff,
            stability,
            wobbleText
        )

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.white
        ]

        let box = CGRect(x: 8, y: 8, width: 200, height: 80)
        info.draw(in: box, withAttributes: attrs)
    }
}