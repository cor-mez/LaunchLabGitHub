//
//  ReprojectionOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class ReprojectionOverlayLayer: CALayer {

    private var latestFrame: VisionFrameData?
    private var latestIntrinsics: CameraIntrinsics?

    // ---------------------------------------------------------
    // MARK: - Update Input
    // ---------------------------------------------------------
    func update(frame: VisionFrameData?, intrinsics: CameraIntrinsics?) {
        self.latestFrame = frame
        self.latestIntrinsics = intrinsics
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard
            let frame = latestFrame,
            let intr = latestIntrinsics
        else { return }

        let bufferWidth = frame.width
        let bufferHeight = frame.height
        let viewSize = bounds.size

        // Placeholder reprojection: draw detected dots + trivial "projection"
        for dot in frame.dots {

            // Detected 2D point
            let detected = dot.position

            // Map to view coordinates
            let viewPoint = VisionOverlaySupport.mapPointFromBufferToView(
                point: detected,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                viewSize: viewSize
            )

            // Simple placeholder logic — real reprojection to come
            let reprojPoint = viewPoint

            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: reprojPoint,
                radius: 3,
                color: UIColor.yellow.cgColor
            )

            VisionOverlaySupport.drawLine(
                context: ctx,
                from: viewPoint,
                to: reprojPoint,
                width: 1,
                color: UIColor.yellow.withAlphaComponent(0.3).cgColor
            )
        }
    }
}
