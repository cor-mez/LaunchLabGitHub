//
//  RSTimingOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class RSTimingOverlayLayer: CALayer {

    private var lineIndex: [Int] = []
    private var timestamps: [Float] = []
    private var frameHeight: Int = 0

    private var minTS: Float = 0
    private var maxTS: Float = 0
    private var avgTS: Float = 0

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(frame: VisionFrameData) {
        lineIndex = frame.rsLineIndex
        timestamps = frame.rsTimestamps
        frameHeight = frame.height

        if timestamps.isEmpty {
            minTS = 0
            maxTS = 0
            avgTS = 0
        } else {
            minTS = timestamps.min() ?? 0
            maxTS = timestamps.max() ?? 0
            let sum = timestamps.reduce(Float(0), +)
            avgTS = sum / Float(timestamps.count)
        }

        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.clear(bounds)

        guard !timestamps.isEmpty, frameHeight > 0 else {
            drawHUD(ctx: ctx)
            return
        }

        let h = CGFloat(frameHeight)
        let tsMin = minTS
        let tsMax = maxTS
        let span = max(0.000001, tsMax - tsMin)

        for (i, ts) in timestamps.enumerated() {
            let norm = CGFloat((ts - tsMin) / span)     // 0 → 1 normalized time

            let color = CGColor(
                red: norm,
                green: 1.0 - norm,
                blue: 0.0,
                alpha: 1.0
            )

            let yPix = timestamps.count > i ? mappedYPixel(index: i) : 0

            ctx.setStrokeColor(color)
            ctx.setLineWidth(0.5)

            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: yPix))
            ctx.addLine(to: CGPoint(x: bounds.width, y: yPix))
            ctx.strokePath()

            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: 4, y: yPix - 2, width: 4, height: 4))

            let label = lineLabel(i: i)
            drawText(label, at: CGPoint(x: 12, y: yPix + 2), ctx: ctx)
        }

        drawHUD(ctx: ctx)
    }

    private func mappedYPixel(index: Int) -> CGFloat {
        guard index < timestamps.count else { return 0 }
        let ts = timestamps[index]
        let tsMin = minTS
        let tsMax = maxTS
        let span = max(0.000001, tsMax - tsMin)
        let frac = CGFloat((ts - tsMin) / span)
        return frac * bounds.height
    }

    private func lineLabel(i: Int) -> String {
        if i < lineIndex.count {
            return "L\(lineIndex[i])"
        } else {
            return "L?"
        }
    }

    private func drawText(_ text: String, at point: CGPoint, ctx: CGContext) {
        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attr)

        UIGraphicsPushContext(ctx)
        str.draw(at: point)
        UIGraphicsPopContext()
    }

    private func drawHUD(ctx: CGContext) {
        let hud = String(
            format: "RS min: %.4f  max: %.4f  avg: %.4f",
            minTS, maxTS, avgTS
        )

        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let str = NSAttributedString(string: hud, attributes: attr)
        let size = str.size()

        let rect = CGRect(x: 8, y: 8, width: size.width, height: size.height)

        UIGraphicsPushContext(ctx)
        str.draw(in: rect)
        UIGraphicsPopContext()
    }
}