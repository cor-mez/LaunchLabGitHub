//
//  DotOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class DotOverlayLayer: BaseOverlayLayer {

    private var dots: [VisionDot] = []

    override func updateWithFrame(_ frame: VisionFrameData) {
        self.dots = frame.dots
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(UIColor.systemYellow.cgColor)

        for d in dots {
            let p = mapper.mapCGPoint(CGPoint(x: CGFloat(d.position.x),
                                              y: CGFloat(d.position.y)))

            let r: CGFloat = 4
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
            ctx.strokeEllipse(in: rect)
        }
    }
}
