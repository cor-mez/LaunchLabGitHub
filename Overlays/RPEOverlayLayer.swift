//
//  RPEOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class RPEOverlayLayer: CALayer {

    private var residuals: [RPEResidual] = []
    private var rms: Float = 0

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
        let rs = frame.rsResiduals
        residuals = rs

        if rs.isEmpty {
            rms = 0
        } else {
            let sum = rs.reduce(Float(0)) { $0 + ($1.errorMag * $1.errorMag) }
            rms = sqrt(sum / Float(rs.count))
        }

        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.clear(bounds)

        guard !residuals.isEmpty else {
            drawRMSText(ctx: ctx)
            return
        }

        for r in residuals {
            let obs = VisionOverlaySupport.mapPointFromBufferToView(
                CGPoint(x: CGFloat(r.observed.x),
                        y: CGFloat(r.observed.y)),
                viewFrame: bounds
            )

            let prj = VisionOverlaySupport.mapPointFromBufferToView(
                CGPoint(x: CGFloat(r.projected.x),
                        y: CGFloat(r.projected.y)),
                viewFrame: bounds
            )

            let color: CGColor = {
                let e = r.errorMag
                if e < 1.0 { return CGColor(red: 0, green: 1, blue: 0, alpha: 1) }
                if e < 3.0 { return CGColor(red: 1, green: 1, blue: 0, alpha: 1) }
                return CGColor(red: 1, green: 0, blue: 0, alpha: 1)
            }()

            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(color)

            ctx.beginPath()
            ctx.move(to: prj)
            ctx.addLine(to: obs)
            ctx.strokePath()

            ctx.setFillColor(color)
            ctx.beginPath()
            ctx.addArc(center: obs, radius: 2.0, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.fillPath()
        }

        drawRMSText(ctx: ctx)
    }

    private func drawRMSText(ctx: CGContext) {
        let text = String(format: "RMS: %.2f px", rms)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()

        let rect = CGRect(x: 8, y: 8, width: size.width, height: size.height)
        UIGraphicsPushContext(ctx)
        attributed.draw(in: rect)
        UIGraphicsPopContext()
    }
}