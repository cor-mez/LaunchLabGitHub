// File: Vision/Overlays/DotTrackingOverlayLayer.swift

import UIKit

final class DotTrackingOverlayLayer: BaseOverlayLayer {

    private var frameData: VisionFrameData?

    override func updateWithFrame(_ frame: VisionFrameData) {
        frameData = frame
        setNeedsDisplay()
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard let f = frameData else { return }

        ctx.setLineWidth(1)
        ctx.setStrokeColor(UIColor.white.cgColor)

        for d in f.dots {
            let p = mapper.mapCGPoint(d.position)
            let rect = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
            ctx.stroke(rect)
        }
    }
}
