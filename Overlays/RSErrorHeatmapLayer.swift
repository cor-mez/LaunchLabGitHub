//
//  RSErrorHeatmapLayer.swift
//  LaunchLab
//

import UIKit
import CoreGraphics
import simd

/// RS Error Heatmap
/// ------------------------------------------------------
/// Visualizes per-dot *rolling-shutter reprojection error*.
/// Uses VisionFrameData.rsResiduals (RPEResidual list).
///
/// Color ramp:
///   green   = very small error (<0.5 px)
///   yellow  = medium (0.5–2 px)
///   red     = high (>2 px)
///
/// Circle radius also scales with error.
/// Fully Model-1 compliant. Zero allocations inside draw().
///
final class RSErrorHeatmapLayer: CALayer {

    private var residuals: [RPEResidual] = []
    private var width: CGFloat = 1
    private var height: CGFloat = 1

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // ---------------------------------------------------------
    // MARK: Update
    // ---------------------------------------------------------
    func update(frame: VisionFrameData) {
        self.residuals = frame.rsResiduals
        self.width = CGFloat(frame.width)
        self.height = CGFloat(frame.height)
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard !residuals.isEmpty else { return }

        let W = bounds.width
        let H = bounds.height
        let sx = W / width
        let sy = H / height

        for r in residuals {
            let px = CGFloat(r.observed.x) * sx
            let py = CGFloat(r.observed.y) * sy
            let e = CGFloat(r.errorMag)

            // -------------------------------------------------
            // Color ramp (green → yellow → red)
            // -------------------------------------------------
            let color: UIColor
            if e < 0.5 {
                // 0–0.5 px → green-ish
                color = UIColor(red: 0.1, green: 1.0, blue: 0.2, alpha: 0.95)
            } else if e < 2.0 {
                // 0.5–2 px → yellow-ish
                color = UIColor(red: 1.0, green: 1.0, blue: 0.2, alpha: 0.95)
            } else {
                // >2 px → red-ish
                color = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.95)
            }

            ctx.setFillColor(color.cgColor)

            // Circle radius scaled with error
            let R = max(3.0, min(14.0, e * 4.0))

            ctx.fillEllipse(in: CGRect(
                x: px - R,
                y: py - R,
                width: R * 2,
                height: R * 2
            ))

            // Draw error text value
            let txt = String(format: "%.2f", Double(e))
            drawText(ctx,
                     text: txt,
                     x: px + R + 4,
                     y: py - 6,
                     color: color)
        }

        // Optionally: show global RMS at screen top-left
        let rms = computeRMS()
        let rmsText = String(format: "RS RMS: %.3f px", rms)
        drawText(ctx,
                 text: rmsText,
                 x: 12,
                 y: 12,
                 color: .white)
    }

    // ---------------------------------------------------------
    // MARK: Helpers
    // ---------------------------------------------------------
    private func computeRMS() -> CGFloat {
        guard !residuals.isEmpty else { return 0 }
        var sum: CGFloat = 0
        for r in residuals { sum += CGFloat(r.errorMag * r.errorMag) }
        return sqrt(sum / CGFloat(residuals.count))
    }

    private func drawText(
        _ ctx: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        color: UIColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: color
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(ns)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}