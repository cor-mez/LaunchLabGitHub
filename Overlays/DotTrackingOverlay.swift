//
//  DotTrackingOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics

final class DotTrackingOverlayLayer: CALayer {

    private var latestFrame: VisionFrameData?

    public func update(frame newFrame: VisionFrameData?) {
        self.latestFrame = newFrame
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        let bufferWidth = frame.width
        let bufferHeight = frame.height
        let size = bounds.size

        for dot in frame.dots {
            let mapped = VisionOverlaySupport.mapPointFromBufferToView(
                point: dot.position,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                viewSize: size
            )

            if let frame = latestFrame {
                ctx.saveGState()
                defer { ctx.restoreGState() }

                ctx.setLineWidth(1.0)

                for dot in frame.dots {
                    guard let v = dot.velocity else { continue }

                    let start = dot.position
                    // Scale down so arrows stay readable even at high speeds.
                    let magnitude = sqrt(v.dx * v.dx + v.dy * v.dy)
                    if magnitude <= 0 { continue }

                    let maxArrowLength: CGFloat = 40.0
                    let scale = min(maxArrowLength / magnitude, 0.25) // clamp for sanity

                    let end = CGPoint(
                        x: start.x + v.dx * scale,
                        y: start.y + v.dy * scale
                    )

                    // Main line
                    ctx.move(to: start)
                    ctx.addLine(to: end)
                    ctx.strokePath()

                    // Simple arrowhead
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let arrowSize: CGFloat = 6.0

                    let left = CGPoint(
                        x: end.x - arrowSize * cos(angle - .pi / 6),
                        y: end.y - arrowSize * sin(angle - .pi / 6)
                    )
                    let right = CGPoint(
                        x: end.x - arrowSize * cos(angle + .pi / 6),
                        y: end.y - arrowSize * sin(angle + .pi / 6)
                    )

                    ctx.move(to: end)
                    ctx.addLine(to: left)
                    ctx.move(to: end)
                    ctx.addLine(to: right)
                    ctx.strokePath()
                }
            }
            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: mapped,
                radius: 4,
                color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
            )
        }
    }
}
