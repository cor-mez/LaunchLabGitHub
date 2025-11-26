// File: Vision/Overlays/RSLineIndexOverlayLayer.swift

import UIKit
import QuartzCore

final class RSLineIndexOverlayLayer: BaseOverlayLayer {

    public var rsIndex: Int = -1 {
        didSet { setNeedsDisplay() }
    }

    override init() {
        super.init()
        isOpaque = false
        contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard rsIndex >= 0 else { return }

        let yView = mapper.mapRowToViewY(CGFloat(rsIndex))

        ctx.setStrokeColor(UIColor.cyan.cgColor)
        ctx.setLineWidth(1.0)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: yView))
        ctx.addLine(to: CGPoint(x: bounds.width, y: yView))
        ctx.strokePath()

        // Label removed (no UIKit text drawing here to avoid CG context issues)
    }
}
