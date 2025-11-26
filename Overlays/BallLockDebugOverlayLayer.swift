// File: Overlays/BallLockDebugOverlayLayer.swift

import UIKit

final class BallLockDebugOverlayLayer: BaseOverlayLayer {

    // MARK: - Public Properties
    var roiCenter: CGPoint?
    var roiRadius: CGFloat?
    var debugInfo: (state: String, Q: Float, CNT: Int, RAD: Float, SYM: Float)?

    // MARK: - Overlay Draw
     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {

        // --- VALID CONTEXT GUARD ---
        let w = ctx.width
        let h = ctx.height
        if w < 4 || h < 4 { return }

        // --- SHAPES (safe to draw without push/pop) ---
        if let c = roiCenter, let r = roiRadius {
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(2.0)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)
            ctx.strokeEllipse(in: rect)
        }

        // --- TEXT (MUST be wrapped in Push/Pop) ---
        guard let info = debugInfo else { return }

        UIGraphicsPushContext(ctx)

        let attrs: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white
        ]

        var y: CGFloat = 14
        func line(_ s: String) {
            s.draw(at: CGPoint(x: 12, y: y), withAttributes: attrs)
            y += 16
        }

        line("STATE: \(info.state)")
        line(String(format: "Q: %.3f", info.Q))
        line("CNT: \(info.CNT)")
        line(String(format: "RAD: %.1f", info.RAD))
        line(String(format: "SYM: %.3f", info.SYM))

        UIGraphicsPopContext()
    }
}
