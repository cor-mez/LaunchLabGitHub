// File: Overlays/DotTestOverlayLayer.swift
//
//  DotTestOverlayLayer.swift
//  LaunchLab
//
//  Developer-only overlay for DotTestMode.
//  Draws FAST9 corner dots and the active ROI circle over a frozen/live frame.
//

import UIKit
import CoreGraphics

final class DotTestOverlayLayer: BaseOverlayLayer {

    // MARK: - Public state

    /// Full-frame coordinates of detected FAST9 corners.
    var detectedPoints: [CGPoint] = []

    /// Size of the underlying camera buffer (pixels).
    var bufferSize: CGSize = .zero

    /// Full-frame ROI used for detection (in buffer pixel space).
    var roiRect: CGRect?

    /// Optional cluster debug (centroid + radius) when enabled.
    var showClusterDebug: Bool = false
    var clusterCentroid: CGPoint?
    var clusterRadiusPx: CGFloat = 0

    // MARK: - Init

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

    // MARK: - Public update API (called from DotTestCoordinator)

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
        let w = ctx.width
        let h = ctx.height
        if w == 0 || h == 0 { return }
        guard bufferSize.width > 0, bufferSize.height > 0 else { return }

        let viewSize = bounds.size
        let imgSize = bufferSize

        // Match UIImageView(.scaleAspectFit) transform:
        // scale by min, center inside view.
        let scale = min(viewSize.width / imgSize.width,
                        viewSize.height / imgSize.height)

        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let offsetX = (viewSize.width - drawW) * 0.5
        let offsetY = (viewSize.height - drawH) * 0.5

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // 1) ROI circle (the *actual* detection ROI).
        if let roi = roiRect {
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.5)

            let centerBuf = CGPoint(x: roi.midX, y: roi.midY)
            let centerView = CGPoint(
                x: offsetX + centerBuf.x * scale,
                y: offsetY + centerBuf.y * scale
            )

            // Use min(width,height) so ROI stays circular even if roi is slightly off-square.
            let radiusPx = min(roi.width, roi.height) * 0.5
            let radiusView = radiusPx * scale

            let rect = CGRect(
                x: centerView.x - radiusView,
                y: centerView.y - radiusView,
                width: radiusView * 2.0,
                height: radiusView * 2.0
            )
            ctx.strokeEllipse(in: rect)
        }

        // 2) Yellow corner dots.
        if !detectedPoints.isEmpty {
            ctx.setFillColor(UIColor.yellow.cgColor)

            for p in detectedPoints {
                // p is in full-frame pixel coordinates.
                let vx = offsetX + p.x * scale
                let vy = offsetY + p.y * scale
                let r: CGFloat = 2.0
                let rect = CGRect(
                    x: vx - r,
                    y: vy - r,
                    width: r * 2.0,
                    height: r * 2.0
                )
                ctx.fillEllipse(in: rect)
            }
        }

        // 3) Optional cluster centroid + radius (for debug).
        if showClusterDebug, let c = clusterCentroid {
            ctx.setStrokeColor(UIColor.systemGreen.cgColor)
            ctx.setLineWidth(1.0)

            let cx = offsetX + c.x * scale
            let cy = offsetY + c.y * scale
            let r = clusterRadiusPx * scale

            // Centroid crosshair.
            ctx.move(to: CGPoint(x: cx - 6, y: cy))
            ctx.addLine(to: CGPoint(x: cx + 6, y: cy))
            ctx.move(to: CGPoint(x: cx, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx, y: cy + 6))
            ctx.strokePath()

            // Cluster radius circle.
            let rect = CGRect(
                x: cx - r,
                y: cy - r,
                width: r * 2.0,
                height: r * 2.0
            )
            ctx.strokeEllipse(in: rect)
        }
    }
}
