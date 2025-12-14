// File: Overlays/PerformanceHUDLayer.swift

import UIKit

final class PerformanceHUDLayer: BaseOverlayLayer {

    struct Stats {
        let fps: Int
        let frameIndex: Int
        let rsConfidence: Float
        let locked: Bool
    }

    var stats: Stats?

     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {

        let w = ctx.width
        let h = ctx.height
        if w < 4 || h < 4 { return }

        guard let stats = stats else { return }

        UIGraphicsPushContext(ctx)

        let attrs: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.green
        ]

        var y: CGFloat = 10
        func line(_ text: String) {
            text.draw(at: CGPoint(x: 12, y: y), withAttributes: attrs)
            y += 16
        }

        line("FPS: \(stats.fps)")
        line("FRAME: \(stats.frameIndex)")
        line(String(format: "RS_CONF: %.2f", stats.rsConfidence))
        line("LOCKED: \(stats.locked ? "YES" : "NO")")

        UIGraphicsPopContext()
    }
}
