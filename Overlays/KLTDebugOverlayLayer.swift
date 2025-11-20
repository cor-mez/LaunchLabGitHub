//
//  KLTDebugOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class KLTDebugOverlayLayer: CALayer {

    private var debugInfo: PyrLKDebugInfo = PyrLKDebugInfo()

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
        debugInfo = frame.lkDebug
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.clear(bounds)

        guard !debugInfo.dots.isEmpty else {
            drawHUD(ctx)
            return
        }

        for dot in debugInfo.dots {
            for lvl in dot.levels {
                drawLevel(lvl, ctx: ctx)
            }
        }

        drawHUD(ctx)
    }

    private func drawLevel(_ lvl: PyrLKLevelDebug, ctx: CGContext) {

        let initialCG = CGPoint(
            x: CGFloat(lvl.initial.x),
            y: CGFloat(lvl.initial.y)
        )
        let refinedCG = CGPoint(
            x: CGFloat(lvl.refined.x),
            y: CGFloat(lvl.refined.y)
        )

        let viewInitial = VisionOverlaySupport.mapPointFromBufferToView(initialCG, viewFrame: bounds)
        let viewRefined = VisionOverlaySupport.mapPointFromBufferToView(refinedCG, viewFrame: bounds)

        let err = lvl.error
        let color: CGColor = {
            if err < 0.5 { return CGColor(red: 0, green: 1, blue: 0, alpha: 1) }
            if err < 1.5 { return CGColor(red: 1, green: 1, blue: 0, alpha: 1) }
            return CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        }()

        ctx.setStrokeColor(color)
        ctx.setLineWidth(1.0)

        ctx.beginPath()
        ctx.move(to: viewInitial)
        ctx.addLine(to: viewRefined)
        ctx.strokePath()

        ctx.setFillColor(color)
        ctx.fillEllipse(
            in: CGRect(
                x: viewRefined.x - 2,
                y: viewRefined.y - 2,
                width: 4,
                height: 4
            )
        )

        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.2))
        ctx.setLineWidth(1.0)
        ctx.stroke(
            CGRect(
                x: viewInitial.x - 8,
                y: viewInitial.y - 8,
                width: 16,
                height: 16
            )
        )

        let label = "L\(lvl.level)"
        drawText(label, at: CGPoint(x: viewInitial.x + 6, y: viewInitial.y - 6), ctx: ctx)
    }

    private func drawText(_ text: String, at p: CGPoint, ctx: CGContext) {
        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let s = NSAttributedString(string: text, attributes: attr)
        UIGraphicsPushContext(ctx)
        s.draw(at: p)
        UIGraphicsPopContext()
    }

    private func drawHUD(_ ctx: CGContext) {
        let totalDots = debugInfo.dots.count
        var unstable = 0

        for dot in debugInfo.dots {
            for lvl in dot.levels where lvl.error > 1.5 {
                unstable += 1
                break
            }
        }

        let text = "KLT dots: \(totalDots)  unstable: \(unstable)"

        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let ns = NSAttributedString(string: text, attributes: attr)
        let size = ns.size()
        let rect = CGRect(x: 8, y: 8, width: size.width, height: size.height)

        UIGraphicsPushContext(ctx)
        ns.draw(in: rect)
        UIGraphicsPopContext()
    }
}