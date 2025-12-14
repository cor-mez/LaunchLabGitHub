//
//  IntrinsicsHeatmapLayer.swift
//  LaunchLab
//

import UIKit

final class IntrinsicsHeatmapLayer: BaseOverlayLayer {

    private var intrinsics: CameraIntrinsics = .zero
    private var size: CGSize = .zero

    override func updateWithFrame(_ frame: VisionFrameData) {
        intrinsics = frame.intrinsics
        size = CGSize(width: frame.width, height: frame.height)
    }

     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard intrinsics.fx > 0 else { return }

        ctx.setFillColor(UIColor.red.withAlphaComponent(0.4).cgColor)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)

        let cx = CGFloat(intrinsics.cx)
        let cy = CGFloat(intrinsics.cy)

        let mapped = mapper.mapCGPoint(CGPoint(x: cx, y: cy))

        let r: CGFloat = 8
        let rect = CGRect(x: mapped.x - r, y: mapped.y - r, width: r*2, height: r*2)

        ctx.fillEllipse(in: rect)
        ctx.strokeEllipse(in: rect)
    }
}
