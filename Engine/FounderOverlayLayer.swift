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
        contentsScale = UIScreen.main.scale
        isOpaque = false
        masksToBounds = false
        cornerRadius = 0          // 🔒 force rectangle
    }

    override init(layer: Any) {
        super.init(layer: layer)
        cornerRadius = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cornerRadius = 0
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

        let rect = roiRectInView()

        ctx.saveGState()

        // 🔒 Explicit rectangle path — no rounding possible
        ctx.setLineWidth(2)
        ctx.setStrokeColor(UIColor.systemGreen.cgColor)
        ctx.setLineDash(phase: 0, lengths: [])

        ctx.addRect(rect)
        ctx.strokePath()

        ctx.restoreGState()

        drawStatus(ctx)
    }

    // MARK: - Status HUD

    private func drawStatus(_ ctx: CGContext) {
        let label = ballLocked ? "LOCKED" : "UNLOCKED"
        let color: UIColor = ballLocked ? .systemGreen : .systemRed

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color
        ]

        label.draw(at: CGPoint(x: 12, y: 12), withAttributes: attrs)

        let barWidth = bounds.width * 0.25
        let barHeight: CGFloat = 8
        let barRect = CGRect(x: 12, y: 34, width: barWidth, height: barHeight)

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.stroke(barRect)

        let clamped = max(0, min(confidence / 20.0, 1))
        let fill = CGRect(
            x: barRect.minX,
            y: barRect.minY,
            width: barRect.width * CGFloat(clamped),
            height: barRect.height
        )

        ctx.setFillColor(color.withAlphaComponent(0.4).cgColor)
        ctx.fill(fill)
    }
}
