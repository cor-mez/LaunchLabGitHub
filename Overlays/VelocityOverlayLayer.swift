//
//  VelocityOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class VelocityOverlayLayer: BaseOverlayLayer {

    private struct Vec {
        let p: CGPoint   // current position (buffer space)
        let v: CGVector  // displacement per frame (buffer space)
    }

    private var vectors: [Vec] = []

    override func updateWithFrame(_ frame: VisionFrameData) {
        vectors.removeAll(keepingCapacity: true)

        for d in frame.dots {
            if let vel = d.velocity {
                vectors.append(Vec(p: d.position, v: vel))
            }
        }
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard !vectors.isEmpty else { return }

        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(UIColor.systemCyan.cgColor)

        // Bigger scale so arrows are clearly visible
        let scale: CGFloat = 5.0
        let minLenSq: CGFloat = 0.5 * 0.5   // ignore tiny jiggles

        for item in vectors {

            let dx = item.v.dx
            let dy = item.v.dy
            let lenSq = dx*dx + dy*dy
            if lenSq < minLenSq { continue }

            // endpoint in BUFFER space
            let endBuffer = CGPoint(
                x: item.p.x + dx * scale,
                y: item.p.y + dy * scale
            )

            let startView = mapper.mapCGPoint(item.p)
            let endView   = mapper.mapCGPoint(endBuffer)

            ctx.move(to: startView)
            ctx.addLine(to: endView)
            ctx.strokePath()
        }
    }
}
