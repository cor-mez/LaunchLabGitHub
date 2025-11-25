//
//  RSBearingVectors.swift
//  LaunchLab
//
//  Canonical RS bearing generator.
//  • Pure logic only — no type redefinitions.
//  • Produces one RSBearing per VisionDot.
//  • Uses VisionTypes.swift for VisionDot, CameraIntrinsics, RSBearing.
//
//  Formula:
//      x_n = (x_px - cx) / fx
//      y_n = (y_px - cy) / fy
//      ray = normalize( [x_n, y_n, 1.0] )
//
//  Each rowIndex is sourced from RSLineIndex.computeRowIndices().
//

import Foundation
import simd
import CoreGraphics

public struct RSBearingVectors {

    /// Compute per-dot camera-space unit bearings for RS-PnP.
    ///
    /// - Parameters:
    ///   - dots: VisionDot array (pixel coordinates)
    ///   - intrinsics: CameraIntrinsics (fx, fy, cx, cy)
    ///   - rowIndices: Per-dot RS row index
    ///
    /// - Returns:
    ///     Parallel array of RSBearing (ray + rowIndex)
    ///
    public static func compute(
        dots: [VisionDot],
        intrinsics: CameraIntrinsics,
        rowIndices: [Int]
    ) -> [RSBearing] {

        let fx = intrinsics.fx
        let fy = intrinsics.fy
        let cx = intrinsics.cx
        let cy = intrinsics.cy

        let count = min(dots.count, rowIndices.count)
        guard count > 0 else { return [] }

        var result: [RSBearing] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let d = dots[i]
            let row = rowIndices[i]

            // Pixel → normalized camera coordinates
            let x = Float(d.position.x)
            let y = Float(d.position.y)

            let xn = (x - cx) / fx
            let yn = (y - cy) / fy

            // Ray = normalize([xn, yn, 1])
            let ray = simd_normalize(SIMD3<Float>(xn, yn, 1.0))

            result.append(RSBearing(ray: ray, rowIndex: row))
        }

        return result
    }
}
