//
//  PoseOverlayLayer.swift
//  LaunchLab
//
//  Batch-7 Fully Corrected Version
//  • Stores VisionFrameData in local property
//  • Never assigns to CALayer.frame
//  • Uses mapper exclusively
//  • Draws only when rspnp.isValid
//

import UIKit
import simd

final class PoseOverlayLayer: BaseOverlayLayer {

    // Store the latest VisionFrameData (NOT a CGRect)
    private var latestFrame: VisionFrameData?

    override func updateWithFrame(_ frame: VisionFrameData) {
        self.latestFrame = frame
        setNeedsDisplay()
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard let frame = latestFrame else { return }
        guard let rs = frame.rspnp, rs.isValid else { return }

        // Camera-space translation
        let T = rs.t

        // Axis length in view-space points
        let axisLen: CGFloat = 40

        // Origin
        let originPx = CGPoint(x: CGFloat(T.x), y: CGFloat(T.y))
        let origin = mapper.mapCGPoint(originPx)

        // Unit axis endpoints (pixel space)
        let xEndPx = CGPoint(x: CGFloat(T.x + 1), y: CGFloat(T.y))
        let yEndPx = CGPoint(x: CGFloat(T.x),     y: CGFloat(T.y + 1))

        let xEnd = mapper.mapCGPoint(xEndPx)
        let yEnd = mapper.mapCGPoint(yEndPx)

        ctx.setLineWidth(2)

        // ---- X axis (red) ----
        ctx.setStrokeColor(UIColor.red.cgColor)
        ctx.beginPath()
        ctx.move(to: origin)
        ctx.addLine(to: CGPoint(
            x: origin.x + (xEnd.x - origin.x) * axisLen,
            y: origin.y + (xEnd.y - origin.y) * axisLen
        ))
        ctx.strokePath()

        // ---- Y axis (green) ----
        ctx.setStrokeColor(UIColor.green.cgColor)
        ctx.beginPath()
        ctx.move(to: origin)
        ctx.addLine(to: CGPoint(
            x: origin.x + (yEnd.x - origin.x) * axisLen,
            y: origin.y + (yEnd.y - origin.y) * axisLen
        ))
        ctx.strokePath()
    }
}
