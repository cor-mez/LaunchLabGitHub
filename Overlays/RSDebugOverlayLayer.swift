// File: Overlays/RSDebugOverlayLayer.swift

import UIKit

final class RSDebugOverlayLayer: BaseOverlayLayer {

    struct DebugInfo {
        let shearSlope: Float
        let rowSpan: Float
        let rsConfidence: Float
        let critical: Bool
    }

    var info: DebugInfo?

    func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {

        let w = ctx.width
        let h = ctx.height
        if w < 4 || h < 4 { return }

        guard let info = info else { return }

        UIGraphicsPushContext(ctx)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: info.critical ? UIColor.red : UIColor.white
        ]

        var y: CGFloat = 10
        func line(_ s: String) {
            s.draw(at: CGPoint(x: 12, y: y), withAttributes: attrs)
            y += 16
        }

        line(String(format: "shear: %.3f", info.shearSlope))
        line(String(format: "rowSpan: %.1f px", info.rowSpan))
        line(String(format: "rsConf: %.2f", info.rsConfidence))
        line("critical: \(info.critical ? "YES" : "NO")")

        UIGraphicsPopContext()
    }
}
