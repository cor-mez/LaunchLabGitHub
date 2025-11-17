//
//  VisionOverlaySupport.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import QuartzCore
import simd

public enum VisionOverlaySupport {

    // ---------------------------------------------------------
    // MARK: - Globals
    // ---------------------------------------------------------
    public static var GLOBAL_SCREEN_SCALE: CGFloat = 1.0

    public static func setScreenScale(_ scale: CGFloat) {
        GLOBAL_SCREEN_SCALE = scale
    }

    // ---------------------------------------------------------
    // MARK: - Aspect-Fit Mapping
    // ---------------------------------------------------------
    public static func mapPointFromBufferToView(
        point: CGPoint,
        bufferWidth: Int,
        bufferHeight: Int,
        viewSize: CGSize
    ) -> CGPoint {

        let bw = CGFloat(bufferWidth)
        let bh = CGFloat(bufferHeight)
        let vw = viewSize.width
        let vh = viewSize.height

        let bufferAspect = bw / bh
        let viewAspect = vw / vh

        var scale: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if bufferAspect > viewAspect {
            scale = vw / bw
            offsetY = (vh - bh * scale) * 0.5
        } else {
            scale = vh / bh
            offsetX = (vw - bw * scale) * 0.5
        }

        return CGPoint(
            x: offsetX + point.x * scale,
            y: offsetY + point.y * scale
        )
    }

    // ---------------------------------------------------------
    // MARK: - Project a single 3D point (Float-safe)
    // ---------------------------------------------------------
    public static func projectPoint3D(
        _ v: SIMD3<Float>,
        intrinsics: CameraIntrinsics
    ) -> CGPoint {

        let X = v.x
        let Y = v.y
        let Z = max(v.z, 0.0001)

        let px = intrinsics.fx * X / Z + intrinsics.cx
        let py = intrinsics.fy * Y / Z + intrinsics.cy

        return CGPoint(x: CGFloat(px), y: CGFloat(py))
    }

    // ---------------------------------------------------------
    // MARK: - Project 3D Camera Axes
    // ---------------------------------------------------------
    public static func project3DAxis(
        rotation: simd_float3x3,
        translation: SIMD3<Float>,
        intrinsics: CameraIntrinsics
    ) -> (origin: CGPoint, x: CGPoint, y: CGPoint, z: CGPoint) {

        let origin = translation

        let axisLength: Float = 0.04
        let xAxis3D = origin + rotation * SIMD3<Float>(axisLength, 0, 0)
        let yAxis3D = origin + rotation * SIMD3<Float>(0, axisLength, 0)
        let zAxis3D = origin + rotation * SIMD3<Float>(0, 0, axisLength)

        return (
            projectPoint3D(origin, intrinsics: intrinsics),
            projectPoint3D(xAxis3D, intrinsics: intrinsics),
            projectPoint3D(yAxis3D, intrinsics: intrinsics),
            projectPoint3D(zAxis3D, intrinsics: intrinsics)
        )
    }

    // ---------------------------------------------------------
    // MARK: - Drawing Helpers
    // ---------------------------------------------------------
    public static func drawCircle(
        context: CGContext,
        at point: CGPoint,
        radius: CGFloat,
        color: CGColor
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(2.0)
        context.addEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.strokePath()
    }

    public static func drawLine(
        context: CGContext,
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat,
        color: CGColor
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }
}
