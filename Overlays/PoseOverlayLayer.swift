//
//  PoseOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class PoseOverlayLayer: CALayer {

    weak var camera: CameraManager?

    override func draw(in ctx: CGContext) {
        guard let camera else { return }

        // MainActor hop to read @Published latestFrame
        let frame = MainActor.assumeIsolated {
            camera.latestFrame
        }
        guard let frame else { return }
        guard let pose = frame.pose else { return }

        // --- Projection: 3D Translation (T) → Pixel (u,v) ---
        let X = pose.T.x
        let Y = pose.T.y
        let Z = pose.T.z

        let fx = frame.intrinsics.fx
        let fy = frame.intrinsics.fy
        let cx = frame.intrinsics.cx
        let cy = frame.intrinsics.cy

        let origin = CGPoint(
            x: CGFloat(fx * X / Z + cx),
            y: CGFloat(fy * Y / Z + cy)
        )

        ctx.setLineWidth(2)

        // X axis (red)
        ctx.setStrokeColor(UIColor.red.cgColor)
        ctx.move(to: origin)
        ctx.addLine(to: CGPoint(x: origin.x + 40, y: origin.y))
        ctx.strokePath()

        // Y axis (green)
        ctx.setStrokeColor(UIColor.green.cgColor)
        ctx.move(to: origin)
        ctx.addLine(to: CGPoint(x: origin.x, y: origin.y + 40))
        ctx.strokePath()
    }
}
