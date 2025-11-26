// File: Engine/FlightUIOverlay.swift

import UIKit

final class FlightUIOverlay: BaseOverlayLayer {

    var ballistics: BallisticsResult?

     func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {

        let w = ctx.width
        let h = ctx.height
        if w < 4 || h < 4 { return }

        guard let b = ballistics else { return }

        // TEXT ONLY (wrapped)
        UIGraphicsPushContext(ctx)

        let attrs: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.white
        ]

        var y: CGFloat = 10
        func line(_ s: String) {
            s.draw(at: CGPoint(x: 12, y: y), withAttributes: attrs)
            y += 18
        }

        line(String(format: "Carry: %.1f m", b.carryDistance))
        line(String(format: "Apex: %.1f m", b.apexHeight))
        line(String(format: "TOF:  %.2f s", b.timeOfFlight))
        line(String(format: "LandA: %.1f°", b.landingAngle))

        UIGraphicsPopContext()
    }
}
