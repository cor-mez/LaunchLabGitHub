//
//  DotTrackingOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import UIKit

final class DotTrackingOverlayLayer: CALayer {

    private var latestFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Public Update Entry
    // ---------------------------------------------------------
    public func update(frame newFrame: VisionFrameData?) {
        self.latestFrame = newFrame
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        let bufferWidth  = frame.width
        let bufferHeight = frame.height
        let viewSize     = bounds.size

        for dot in frame.dots {

            // -----------------------------------------------------
            // 1. Map dot to view space
            // -----------------------------------------------------
            let mapped = VisionOverlaySupport.mapPointFromBufferToView(
                point: dot.position,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                viewSize: viewSize
            )

            // -----------------------------------------------------
            // 2. Choose dot color by velocity stability
            // -----------------------------------------------------
            let color: CGColor
            if let v = dot.velocity {
                let mag = sqrt(v.dx * v.dx + v.dy * v.dy)
                color = (mag < 25)
                    ? UIColor.green.cgColor
                    : UIColor.yellow.cgColor
            } else {
                color = UIColor.white.cgColor
            }

            // -----------------------------------------------------
            // 3. Draw Dot
            // -----------------------------------------------------
            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: mapped,
                radius: 4,
                color: color
            )

            // -----------------------------------------------------
            // 4. Draw Dot ID
            // -----------------------------------------------------
            let idString = "\(dot.id)"
            let idAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .medium),
                .foregroundColor: UIColor.white
            ]

            idString.draw(
                at: CGPoint(x: mapped.x + 5, y: mapped.y - 5),
                withAttributes: idAttrs
            )

            // -----------------------------------------------------
            // 5. Draw Velocity Vector + Arrowhead
            // -----------------------------------------------------
            if let v = dot.velocity {

                let vx = v.dx
                let vy = v.dy
                let magnitude = sqrt(vx*vx + vy*vy)

                // Clamp arrow length
                let maxLength: CGFloat = 40
                let scale = min(maxLength / max(magnitude, 1), 4.0)

                let end = CGPoint(
                    x: mapped.x + vx * scale,
                    y: mapped.y + vy * scale
                )

                // ---- Main arrow line ----
                ctx.setStrokeColor(UIColor.cyan.cgColor)
                ctx.setLineWidth(1)
                ctx.beginPath()
                ctx.move(to: mapped)
                ctx.addLine(to: end)
                ctx.strokePath()

                // ---- Arrowhead ----
                let angle = atan2(end.y - mapped.y, end.x - mapped.x)
                let arrowSize: CGFloat = 6.0

                let left = CGPoint(
                    x: end.x - arrowSize * cos(angle - .pi / 6),
                    y: end.y - arrowSize * sin(angle - .pi / 6)
                )

                let right = CGPoint(
                    x: end.x - arrowSize * cos(angle + .pi / 6),
                    y: end.y - arrowSize * sin(angle + .pi / 6)
                )

                ctx.beginPath()
                ctx.move(to: end)
                ctx.addLine(to: left)
                ctx.move(to: end)
                ctx.addLine(to: right)
                ctx.strokePath()
            }
        }
    }
}
