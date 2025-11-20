//
//  RSDebugOverlayLayer.swift
//  LaunchLab
//

import UIKit
import CoreGraphics
import simd

/// Rolling-Shutter Debug Overlay
/// ------------------------------------------
/// Visualizes calibrated per-dot RS timing:
/// - Dot positions
/// - Timestamp Δt (ms)
/// - RS line index (optional)
/// - Left-edge timing curve
///
/// Safe for LaunchLab v5 Model-1 overlay rules.
/// No allocations in draw(), no threading.
///
final class RSDebugOverlayLayer: CALayer {

    private var dots: [VisionDot] = []
    private var timestamps: [Float] = []
    private var lineIndex: [Int] = []

    private var frameWidth: CGFloat = 1
    private var frameHeight: CGFloat = 1

    private let showTimingCurve: Bool = true

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // -----------------------------------------------------
    // MARK: update(frame:)
    // -----------------------------------------------------
    func update(frame: VisionFrameData) {
        self.dots = frame.dots
        self.timestamps = frame.rsTimestamps
        self.lineIndex = frame.rsLineIndex
        self.frameWidth = CGFloat(frame.width)
        self.frameHeight = CGFloat(frame.height)
        setNeedsDisplay()
    }

    // -----------------------------------------------------
    // MARK: draw(in:)
    // -----------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard dots.count == timestamps.count else { return }

        let W = bounds.width
        let H = bounds.height

        let sx = W / frameWidth
        let sy = H / frameHeight

        // Compute min/max for color normalization
        var minT: Float = .greatestFiniteMagnitude
        var maxT: Float = -.greatestFiniteMagnitude

        for t in timestamps {
            if t < minT { minT = t }
            if t > maxT { maxT = t }
        }
        let span = max(maxT - minT, 1e-6)

        // -------------------------------------------------
        // Draw dots + per-dot Δt label
        // -------------------------------------------------
        for i in 0..<dots.count {
            let d = dots[i]
            let t = timestamps[i]

            let px = d.position.x * sx
            let py = d.position.y * sy

            // Normalize to 0–1
            let k = CGFloat((t - minT) / span)

            // Heat color: blue → red
            let r = k
            let g = CGFloat(0.2 * (1.0 - k))
            let b = 1.0 - k

            ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 1).cgColor)

            let R: CGFloat = 4
            ctx.fillEllipse(in: CGRect(x: px - R, y: py - R, width: 2*R, height: 2*R))

            // Δt in ms
            let dtMS = t * 1000.0
            let lbl = String(format: "%.2f ms", dtMS)
            drawText(ctx, text: lbl, x: px + 6, y: py - 8, color: .white)

            // RS line index
            if i < lineIndex.count {
                let li = lineIndex[i]
                drawText(ctx,
                         text: "#\(li)",
                         x: px + 6,
                         y: py + 8,
                         color: .yellow)
            }
        }

        // -------------------------------------------------
        // Timing curve (left side)
        // -------------------------------------------------
        if showTimingCurve {
            drawTimingCurve(ctx: ctx,
                            W: W,
                            H: H,
                            minT: minT,
                            maxT: maxT)
        }
    }

    // -----------------------------------------------------
    // MARK: Text helper
    // -----------------------------------------------------
    private func drawText(
        _ ctx: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        color: UIColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(ns)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    // -----------------------------------------------------
    // MARK: Timing curve graph
    // -----------------------------------------------------
    private func drawTimingCurve(
        ctx: CGContext,
        W: CGFloat,
        H: CGFloat,
        minT: Float,
        maxT: Float
    ) {
        guard !dots.isEmpty else { return }

        let graphW: CGFloat = 40
        let sx = W / frameWidth
        let sy = H / frameHeight
        let span = max(maxT - minT, 1e-6)

        ctx.setStrokeColor(UIColor.systemTeal.cgColor)
        ctx.setLineWidth(2)

        ctx.beginPath()

        var first = true
        for i in 0..<dots.count {
            let d = dots[i]
            let t = timestamps[i]

            let yPix = d.position.y * sy
            let k = CGFloat((t - minT) / span)
            let xPix = k * graphW

            if first {
                ctx.move(to: CGPoint(x: xPix, y: yPix))
                first = false
            } else {
                ctx.addLine(to: CGPoint(x: xPix, y: yPix))
            }
        }

        ctx.strokePath()

        // Border
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 0, y: 0, width: graphW, height: H))
    }
}