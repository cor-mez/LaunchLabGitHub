import UIKit

@MainActor
final class FounderOverlayLayer: CALayer {
    private var roi: CGRect = .zero
    private var fullSize: CGSize = .zero
    private var ballLocked: Bool = false
    private var confidence: Float = 0

    func update(roi: CGRect, fullSize: CGSize, ballLocked: Bool, confidence: Float) {
        self.roi = roi
        self.fullSize = fullSize
        self.ballLocked = ballLocked
        self.confidence = confidence
        setNeedsDisplay()
    }

    private func roiRectInView() -> CGRect {
        guard fullSize.width > 0, fullSize.height > 0 else { return .zero }

        let viewW = bounds.width
        let viewH = bounds.height

        let sx = viewW / fullSize.width
        let sy = viewH / fullSize.height
        let scale = min(sx, sy)

        let rw = roi.width  * scale
        let rh = roi.height * scale
        let rx = roi.origin.x * scale
        let ry = roi.origin.y * scale

        return CGRect(x: rx, y: ry, width: rw, height: rh)
    }

    override func draw(in ctx: CGContext) {
        guard roi.width > 0, roi.height > 0 else { return }

        let roiView = roiRectInView()

        ctx.setStrokeColor(UIColor.systemCyan.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(roiView)

        let corner: CGFloat = 8
        let highlight = CGRect(x: roiView.minX - corner,
                               y: roiView.minY - corner,
                               width: roiView.width + corner * 2,
                               height: roiView.height + corner * 2)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineDash(phase: 0, lengths: [10, 6])
        ctx.stroke(highlight)
        ctx.setLineDash(phase: 0, lengths: [])

        drawStatus(ctx)
    }

    private func drawStatus(_ ctx: CGContext) {
        let stateText = ballLocked ? "LOCKED" : "UNLOCKED"
        let color: UIColor = ballLocked ? .systemGreen : .systemRed

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color
        ]

        let statusPoint = CGPoint(x: 12, y: 12)
        stateText.draw(at: statusPoint, withAttributes: attrs)

        let confWidth = bounds.width * 0.25
        let confHeight: CGFloat = 8
        let confRect = CGRect(x: 12, y: statusPoint.y + 20, width: confWidth, height: confHeight)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.stroke(confRect)

        let clamped = max(0, min(confidence / 20.0, 1))
        let fill = CGRect(x: confRect.minX,
                          y: confRect.minY,
                          width: confRect.width * CGFloat(clamped),
                          height: confRect.height)
        ctx.setFillColor(color.withAlphaComponent(0.4).cgColor)
        ctx.fill(fill)

        let confString = String(format: "conf=%.1f", confidence)
        confString.draw(at: CGPoint(x: confRect.minX, y: confRect.maxY + 6),
                        withAttributes: [
                            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                            .foregroundColor: UIColor.white
                        ])
    }
}
