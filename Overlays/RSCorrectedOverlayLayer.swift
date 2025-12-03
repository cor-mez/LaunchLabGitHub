//
//  RSCorrectedOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class RSCorrectedOverlayLayer: BaseOverlayLayer {

    private var corrected: [CGPoint] = []

    override func updateWithFrame(_ frame: VisionFrameData) {
        corrected.removeAll(keepingCapacity: true)

        if let pts = frame.correctedPoints {
            corrected = pts   // each element is already a CGPoint
        }
    }

     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(UIColor.systemGreen.cgColor)

        for p in corrected {
            let mapped = mapper.mapCGPoint(p)
            let r: CGFloat = 3
            let rect = CGRect(
                x: mapped.x - r,
                y: mapped.y - r,
                width: r * 2,
                height: r * 2
            )
            ctx.strokeEllipse(in: rect)
        }
    }
}
