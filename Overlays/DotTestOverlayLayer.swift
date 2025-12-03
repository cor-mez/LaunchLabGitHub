//
//  DotTestOverlayLayer.swift
//  LaunchLab
//

import UIKit
import CoreGraphics

final class DotTestOverlayLayer: BaseOverlayLayer {

    // MARK: - State

    var detectedPoints: [CGPoint] = []
    var bufferSize: CGSize = .zero
    var roiRect: CGRect?

    var showClusterDebug: Bool = false
    var clusterCentroid: CGPoint?
    var clusterRadiusPx: CGFloat = 0

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    // MARK: - API

    func update(points: [CGPoint], bufferSize: CGSize, roiRect: CGRect?) {
        self.detectedPoints = points
        self.bufferSize = bufferSize
        self.roiRect = roiRect
        setNeedsDisplay()
    }

    func updateClusterDebug(centroid: CGPoint?, radiusPx: CGFloat) {
        self.clusterCentroid = centroid
        self.clusterRadiusPx = radiusPx
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(in ctx: CGContext) {
        guard bufferSize.width > 0,
              bufferSize.height > 0 else { return }

        let viewSize = bounds.size
        let imgSize = bufferSize

        // Match UIImageView(.scaleAspectFit)
        let scale = min(viewSize.width / imgSize.width,
                        viewSize.height / imgSize.height)

        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale

        let offsetX = (viewSize.width  - drawW) * 0.5
        let offsetY = (viewSize.height - drawH) * 0.5

        let rctx = UIGraphicsGetCurrentContext()!
        rctx.saveGState()
        defer { rctx.restoreGState() }

        // -------------------------------
        // ROI Circle (always full-frame)
        // -------------------------------
        if let roi = roiRect {
            let center = CGPoint(
                x: offsetX + roi.midX * scale,
                y: offsetY + roi.midY * scale
            )
            let radius = 0.5 * min(roi.width, roi.height) * scale

            rctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            rctx.setLineWidth(1.5)
            rctx.strokeEllipse(
                in: CGRect(x: center.x - radius,
                           y: center.y - radius,
                           width: radius * 2,
                           height: radius * 2)
            )
        }

        // -------------------------------
        // Yellow FAST9 Points
        //-------------------------------
        rctx.setFillColor(UIColor.yellow.cgColor)
        for p in detectedPoints {
            let vx = offsetX + p.x * scale
            let vy = offsetY + p.y * scale
            let dotRect = CGRect(x: vx - 2,
                                 y: vy - 2,
                                 width: 4,
                                 height: 4)
            rctx.fillEllipse(in: dotRect)
        }

        // -------------------------------
        // Optional cluster debug
        // -------------------------------
        if showClusterDebug, let c = clusterCentroid {
            let cx = offsetX + c.x * scale
            let cy = offsetY + c.y * scale

            rctx.setStrokeColor(UIColor.green.cgColor)
            rctx.setLineWidth(1.0)

            // Crosshair
            rctx.move(to: CGPoint(x: cx - 6, y: cy))
            rctx.addLine(to: CGPoint(x: cx + 6, y: cy))
            rctx.move(to: CGPoint(x: cx, y: cy - 6))
            rctx.addLine(to: CGPoint(x: cx, y: cy + 6))
            rctx.strokePath()

            let radius = clusterRadiusPx * scale
            rctx.strokeEllipse(
                in: CGRect(x: cx - radius,
                           y: cy - radius,
                           width: radius * 2,
                           height: radius * 2)
            )
        }
    }
}