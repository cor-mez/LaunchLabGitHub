// File: Overlays/ReprojectionOverlayLayer.swift

import UIKit
import QuartzCore

final class ReprojectionOverlayLayer: BaseOverlayLayer {

    private var latestFrame: VisionFrameData?

    override func updateWithFrame(_ frame: VisionFrameData) {
        self.latestFrame = frame
        setNeedsDisplay()
    }

    func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard let frame = latestFrame else { return }
        guard let corrected = frame.correctedPoints else { return }
        guard let residuals = frame.residuals else { return }

        let count = min(corrected.count, residuals.count)
        guard count > 0 else { return }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        for i in 0..<count {
            let cp = corrected[i]      // cp is a CGPoint
            let r  = residuals[i].error

            // Corrected point → view
            let detected = mapper.mapCGPoint(cp)

            // Predicted = cp + residual
            let predictedPx = CGPoint(
                x: cp.x + CGFloat(r.x),
                y: cp.y + CGFloat(r.y)
            )
            let predicted = mapper.mapCGPoint(predictedPx)

            // --- Draw corrected (yellow) ---
            ctx.setFillColor(UIColor.yellow.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: detected.x - 3,
                y: detected.y - 3,
                width: 6, height: 6
            ))

            // --- Draw predicted (cyan) ---
            ctx.setStrokeColor(UIColor.cyan.cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(
                x: predicted.x - 4,
                y: predicted.y - 4,
                width: 8, height: 8
            ))

            // --- Error vector (red line) ---
            ctx.setStrokeColor(UIColor.red.withAlphaComponent(0.6).cgColor)
            ctx.beginPath()
            ctx.move(to: detected)
            ctx.addLine(to: predicted)
            ctx.strokePath()
        }
    }
}
