//
//  FounderOverlayLayer.swift
//  LaunchLab
//
//  Engine-truth ROI overlay.
//  Safe CoreGraphics + UIKit interop.
//

import UIKit

@MainActor
final class FounderOverlayLayer: CALayer {

    // MARK: - State

    private var roi: CGRect = .zero
    private var fullSize: CGSize = .zero
    private var ballLocked: Bool = false
    private var confidence: Float = 0

    // MARK: - Init

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
        contentsScale = UIScreen.main.scale
        isOpaque = false
        masksToBounds = false
    }

    // MARK: - Public API

    func update(
        roi: CGRect,
        fullSize: CGSize,
        ballLocked: Bool,
        confidence: Float
    ) {
        self.roi = roi
        self.fullSize = fullSize
        self.ballLocked = ballLocked
        self.confidence = confidence
        setNeedsDisplay()
    }

    // MARK: - Coordinate Mapping

    private func roiRectInView() -> CGRect {
        guard fullSize.width > 0, fullSize.height > 0 else { return .zero }

        let viewW = bounds.width
        let viewH = bounds.height

        let sx = viewW / fullSize.width
        let sy = viewH / fullSize.height
        let scale = min(sx, sy)

        let offsetX = (viewW - fullSize.width * scale) * 0.5
        let offsetY = (viewH - fullSize.height * scale) * 0.5

        return CGRect(
            x: roi.origin.x * scale + offsetX,
            y: roi.origin.y * scale + offsetY,
            width: roi.width * scale,
            height: roi.height * scale
        )
    }

    // MARK: - Drawing

    override func draw(in ctx: CGContext) {
        guard roi.width > 0, roi.height > 0 else { return }

        // -------------------------------
        // Geometry (pure CoreGraphics)
        // -------------------------------
        let rect = roiRectInView()

        ctx.saveGState()
        ctx.setLineWidth(2)
        ctx.setStrokeColor(
            (ballLocked ? UIColor.systemGreen : UIColor.systemRed).cgColor
        )
        ctx.addRect(rect)
        ctx.strokePath()
        ctx.restoreGState()

        // -------------------------------
        // UIKit text + bars (requires push)
        // -------------------------------
        UIGraphicsPushContext(ctx)
        drawStatusUIKit()
        UIGraphicsPopContext()
    }

    // MARK: - UIKit-safe HUD

    private func drawStatusUIKit() {
        let label = ballLocked ? "LOCKED" : "UNLOCKED"
        let color: UIColor = ballLocked ? .systemGreen : .systemRed

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color
        ]

        label.draw(at: CGPoint(x: 12, y: 12), withAttributes: attrs)

        // Confidence bar
        let barW = bounds.width * 0.25
        let barH: CGFloat = 8
        let barRect = CGRect(x: 12, y: 34, width: barW, height: barH)

        UIColor.white.setStroke()
        UIBezierPath(rect: barRect).stroke()

        let clamped = max(0, min(confidence / 20.0, 1))
        let fillRect = CGRect(
            x: barRect.minX,
            y: barRect.minY,
            width: barRect.width * CGFloat(clamped),
            height: barRect.height
        )

        color.withAlphaComponent(0.4).setFill()
        UIBezierPath(rect: fillRect).fill()
    }
}
