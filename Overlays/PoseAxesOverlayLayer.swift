//
//  PoseAxesOverlayLayer.swift
//  LaunchLab
//

import UIKit
import simd

final class PoseAxesOverlayLayer: BaseOverlayLayer {

    private var pose: RSPnPResult?
    private var intr: CameraIntrinsics = .zero
    private var size: CGSize = .zero

    override func updateWithFrame(_ frame: VisionFrameData) {
        pose = frame.rspnp     // non-optional RSPnPResult
        intr = frame.intrinsics
        size = CGSize(width: frame.width, height: frame.height)
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard let pose = pose, pose.isValid else { return }

        // Axes: unit vectors in camera frame
        let origin = SIMD3<Float>(0,0,0)
        let xAxis  = SIMD3<Float>(0.05, 0, 0)
        let yAxis  = SIMD3<Float>(0, 0.05, 0)
        let zAxis  = SIMD3<Float>(0, 0, 0.05)

        let pts3D = [origin, xAxis, yAxis, zAxis]

        // Project -> 2D
        let pts2D = pts3D.map { p -> CGPoint in
            let cam = pose.R * p + pose.t
            return project(cam, intr: intr)
        }

        let o = mapper.mapCGPoint(pts2D[0])
        let px = mapper.mapCGPoint(pts2D[1])
        let py = mapper.mapCGPoint(pts2D[2])
        let pz = mapper.mapCGPoint(pts2D[3])

        ctx.setLineWidth(2.0)

        // X axis (red)
        ctx.setStrokeColor(UIColor.systemRed.cgColor)
        ctx.move(to: o); ctx.addLine(to: px); ctx.strokePath()

        // Y axis (green)
        ctx.setStrokeColor(UIColor.systemGreen.cgColor)
        ctx.move(to: o); ctx.addLine(to: py); ctx.strokePath()

        // Z axis (blue)
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.move(to: o); ctx.addLine(to: pz); ctx.strokePath()
    }

    private func project(_ p: SIMD3<Float>, intr: CameraIntrinsics) -> CGPoint {
        let x = CGFloat(p.x / p.z) * CGFloat(intr.fx) + CGFloat(intr.cx)
        let y = CGFloat(p.y / p.z) * CGFloat(intr.fy) + CGFloat(intr.cy)
        return CGPoint(x: x, y: y)
    }
}
