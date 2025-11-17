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

            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: mapped,
                radius: 4,
                color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
            )
        }
    }
}
