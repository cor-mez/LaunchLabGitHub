// DotTestOverlayLayer.swift v4A

import UIKit
import CoreGraphics

final class DotTestOverlayLayer: CALayer {

    private var pointsCPU: [CGPoint] = []
    private var pointsGPU: [CGPoint] = []
    private var roiRect: CGRect = .zero
    private var bufferSize: CGSize = .zero

    func update(
        pointsCPU: [CGPoint],
        pointsGPU: [CGPoint],
        bufferSize: CGSize,
        roiRect: CGRect?
    ) {
        self.pointsCPU = pointsCPU
        self.pointsGPU = pointsGPU
        self.bufferSize = bufferSize
        self.roiRect = roiRect ?? .zero
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        let w = bounds.width
        let h = bounds.height
        if w <= 0 || h <= 0 { return }
        if bufferSize.width <= 0 || bufferSize.height <= 0 { return }

        let sx = w / bufferSize.width
        let sy = h / bufferSize.height
        let scale = min(sx, sy)

        ctx.setLineWidth(1.0)

        if roiRect.width > 0 && roiRect.height > 0 {
            let rx = roiRect.origin.x * scale
            let ry = roiRect.origin.y * scale
            let rw = roiRect.width * scale
            let rh = roiRect.height * scale
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.stroke(CGRect(x: rx, y: ry, width: rw, height: rh))
        }

        if pointsCPU.count > 0 {
            ctx.setFillColor(UIColor.yellow.cgColor)
            for p in pointsCPU {
                let px = p.x * scale
                let py = p.y * scale
                let r = CGRect(x: px - 2, y: py - 2, width: 4, height: 4)
                ctx.fillEllipse(in: r)
            }
        }

        if pointsGPU.count > 0 {
            ctx.setFillColor(UIColor.cyan.cgColor)
            for p in pointsGPU {
                let px = p.x * scale
                let py = p.y * scale
                let r = CGRect(x: px - 2, y: py - 2, width: 4, height: 4)
                ctx.fillEllipse(in: r)
            }
        }
    }
}
