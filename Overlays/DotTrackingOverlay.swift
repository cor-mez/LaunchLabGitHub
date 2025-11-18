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
            // 1. View-space coordinate mapping
            // -----------------------------------------------------
            let mapped = VisionOverlaySupport.mapPointFromBufferToView(
                point: dot.position,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                viewSize: viewSize
            )

            // ------------------------
            // Dot color state:
            // - stable velocity = green
            // - unstable velocity = yellow
            // - no velocity = white
            // ------------------------
            let color: CGColor
            if let v = dot.velocity {
                let mag = sqrt(v.dx*v.dx + v.dy*v.dy)
                if mag < 25 {
                    color = CGColor(red: 0, green: 1, blue: 0, alpha: 1)   // stable = green
                } else {
                    color = CGColor(red: 1, green: 1, blue: 0, alpha: 1)   // unstable = yellow
                }
            } else {
                color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)       // no velocity = white
            }

            // -----------------------------------------------------
            // 2. Draw Dot
            // -----------------------------------------------------
            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: mapped,
                radius: 4,
                color: color
            )

            // -----------------------------------------------------
            // 3. Draw Dot ID
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
            // 4. Draw Velocity Vector (scaled)
            // -----------------------------------------------------
            if let v = dot.velocity {
                let scale: CGFloat = 4.0
                let end = CGPoint(
                    x: mapped.x + v.dx * scale,
                    y: mapped.y + v.dy * scale
                )

                ctx.setStrokeColor(UIColor.cyan.cgColor)
                ctx.setLineWidth(1)
                ctx.beginPath()
                ctx.move(to: mapped)
                ctx.addLine(to: end)
                ctx.strokePath()
            }
        }
    }
}