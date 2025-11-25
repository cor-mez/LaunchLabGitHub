//
//  RSRowOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class RSRowOverlayLayer: BaseOverlayLayer {

    private var rows: [Int] = []

    override func updateWithFrame(_ frame: VisionFrameData) {
        var tmp: [Int] = []
        tmp.reserveCapacity(frame.dots.count)

        for d in frame.dots {
            tmp.append(Int(d.position.y))
        }
        self.rows = tmp
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard rows.count > 0 else { return }

        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(UIColor.magenta.cgColor)

        for r in rows {
            let y = mapper.mapRowToViewY(CGFloat(r))
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: mapper.viewSize.width, y: y))
            ctx.strokePath()
        }
    }
}
