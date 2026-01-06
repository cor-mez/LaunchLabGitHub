//
//  ROIRectOverlayLayer.swift
//  LaunchLab
//
//  Minimal ROI rectangle overlay.
//  No text. No bars. No CoreGraphics font drawing.
//  Pure geometry mapping: engine-space ROI -> view-space (aspect-fit).
//

import UIKit

@MainActor
final class ROIRectOverlayLayer: CAShapeLayer {

    private var roi: CGRect = .zero
    private var fullSize: CGSize = .zero

    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        fillColor = UIColor.clear.cgColor
        strokeColor = UIColor.systemGreen.cgColor
        lineWidth = 2.0
        lineDashPattern = [] // solid
        contentsScale = UIScreen.main.scale
    }

    func update(roi: CGRect, fullSize: CGSize, in viewBounds: CGRect) {
        self.roi = roi
        self.fullSize = fullSize
        self.frame = viewBounds
        self.path = roiPathInView().cgPath
    }

    private func roiPathInView() -> UIBezierPath {
        guard fullSize.width > 0, fullSize.height > 0, roi.width > 0, roi.height > 0 else {
            return UIBezierPath()
        }

        // Aspect-fit mapping from engine fullSize to view bounds.
        let viewW = bounds.width
        let viewH = bounds.height

        let sx = viewW / fullSize.width
        let sy = viewH / fullSize.height
        let scale = min(sx, sy)

        let offsetX = (viewW - fullSize.width * scale) * 0.5
        let offsetY = (viewH - fullSize.height * scale) * 0.5

        let rect = CGRect(
            x: roi.origin.x * scale + offsetX,
            y: roi.origin.y * scale + offsetY,
            width: roi.width * scale,
            height: roi.height * scale
        )

        return UIBezierPath(rect: rect.integral)
    }
}
