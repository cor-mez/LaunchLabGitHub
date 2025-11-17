//
//  PoseOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import simd

final class PoseOverlayLayer: CALayer {

    private var latestFrame: VisionFrameData?
    private var latestIntrinsics: CameraIntrinsics?

    // ---------------------------------------------------------
    // MARK: - Update
    // ---------------------------------------------------------
    func update(frame newFrame: VisionFrameData?, intrinsics: CameraIntrinsics?) {
        self.latestFrame = newFrame
        self.latestIntrinsics = intrinsics
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard
            let frame = latestFrame,
            let pose = frame.pose,
            let intr = latestIntrinsics
        else { return }

        let viewSize = bounds.size

        // -----------------------------------------------------
        // Step 1: Project origin + axes in 2D buffer coordinates
        // -----------------------------------------------------
        let axes = VisionOverlaySupport.project3DAxis(
            rotation: pose.rotation,
            translation: pose.translation,
            intrinsics: intr
        )

        // axes.origin, axes.x, axes.y, axes.z are in buffer-space (pixels)

        // -----------------------------------------------------
        // Step 2: Map buffer-space to view-space
        // -----------------------------------------------------
        let o = VisionOverlaySupport.mapPointFromBufferToView(
            point: axes.origin,
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: viewSize
        )

        let xEnd = VisionOverlaySupport.mapPointFromBufferToView(
            point: axes.x,
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: viewSize
        )

        let yEnd = VisionOverlaySupport.mapPointFromBufferToView(
            point: axes.y,
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: viewSize
        )

        let zEnd = VisionOverlaySupport.mapPointFromBufferToView(
            point: axes.z,
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: viewSize
        )

        // -----------------------------------------------------
        // Step 3: Draw axes using updated API
        // -----------------------------------------------------
        VisionOverlaySupport.drawLine(
            context: ctx,
            from: o,
            to: xEnd,
            width: 3,
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        )

        VisionOverlaySupport.drawLine(
            context: ctx,
            from: o,
            to: yEnd,
            width: 3,
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        )

        VisionOverlaySupport.drawLine(
            context: ctx,
            from: o,
            to: zEnd,
            width: 3,
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        )
    }
}
