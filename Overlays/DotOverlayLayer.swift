//
//  DotOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class DotOverlayLayer: CALayer {

    weak var pipeline: VisionPipeline?

    override func draw(in ctx: CGContext) {
        guard let frame = pipeline?.latestFrame else { return }

        ctx.setLineWidth(2)
        ctx.setFillColor(UIColor.yellow.cgColor)

        for dot in frame.dots {
            let p = CGPoint(x: dot.position.x, y: dot.position.y)
            let r: CGFloat = 3.0

            ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r,
                                      width: r*2, height: r*2))
            ctx.fillPath()
        }
    }
}
