//
//  DotOverlayLayer.swift
//

import UIKit

final class DotOverlayLayer: BaseOverlayLayer {

    private var mapper: OverlayMapper?
    private var points: [CGPoint] = []

    override func assignMapper(_ mapper: OverlayMapper) {
        self.mapper = mapper
    }

    override func updateWithFrame(_ frame: VisionFrameData) {
        points = frame.dots.map { $0.position }
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard let mapper = mapper else { return }
        guard !points.isEmpty else { return }

        ctx.setFillColor(UIColor.yellow.cgColor)
        for p in points {
            let v = mapper.mapCGPoint(p)
            let r: CGFloat = 2.0
            ctx.fillEllipse(in: CGRect(x: v.x - r, y: v.y - r, width: 2*r, height: 2*r))
        }
    }
}
