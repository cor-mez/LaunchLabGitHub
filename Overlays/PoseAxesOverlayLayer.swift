//
//  PoseAxesOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import simd
import UIKit

final class PoseAxesOverlayLayer: CALayer {

    // Latest processed frame
    private var latestFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Public Update
    // ---------------------------------------------------------
    public func update(frame: VisionFrameData?) {
        latestFrame = frame
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        // Prefer RS-PnP pose if available
        let R: simd_float3x3
        let T: SIMD3<Float>

        if let rs = frame.rspnp {
            R = rs.R
            T = rs.t
        } else if let pose = frame.pose {
            R = pose.R
            T = pose.T
        } else {
            return
        }

        let K = frame.intrinsics.matrix

        let size = bounds.size
        let bw = Float(frame.width)
        let bh = Float(frame.height)

        // ---------------------------------------------------------
        // Helper: 3D → 2D projection
        // ---------------------------------------------------------
        func project(_ p: SIMD3<Float>) -> CGPoint {
            let x = (K[0,0] * p.x + K[0,2] * p.z) / p.z
            let y = (K[1,1] * p.y + K[1,2] * p.z) / p.z

            let vx = CGFloat(x / bw) * size.width
            let vy = CGFloat(y / bh) * size.height
            return CGPoint(x: vx, y: vy)
        }

        // ---------------------------------------------------------
        // Compute camera-frame basis vectors
        // ---------------------------------------------------------
        let origin3D = T

        // 3D axis length (in meters)
        let L: Float = 0.05

        let x3D = origin3D + R * SIMD3<Float>(L, 0, 0)
        let y3D = origin3D + R * SIMD3<Float>(0, L, 0)
        let z3D = origin3D + R * SIMD3<Float>(0, 0, L)

        let origin2D = project(origin3D)
        let x2D = project(x3D)
        let y2D = project(y3D)
        let z2D = project(z3D)

        ctx.setLineWidth(3)

        // ---------------------------------------------------------
        // Draw X (red)
        // ---------------------------------------------------------
        ctx.setStrokeColor(UIColor.red.cgColor)
        ctx.beginPath()
        ctx.move(to: origin2D)
        ctx.addLine(to: x2D)
        ctx.strokePath()

        // ---------------------------------------------------------
        // Draw Y (green)
        // ---------------------------------------------------------
        ctx.setStrokeColor(UIColor.green.cgColor)
        ctx.beginPath()
        ctx.move(to: origin2D)
        ctx.addLine(to: y2D)
        ctx.strokePath()

        // ---------------------------------------------------------
        // Draw Z (blue)
        // ---------------------------------------------------------
        ctx.setStrokeColor(UIColor.blue.cgColor)
        ctx.beginPath()
        ctx.move(to: origin2D)
        ctx.addLine(to: z2D)
        ctx.strokePath()
    }
}