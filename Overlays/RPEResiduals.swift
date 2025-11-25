//
//  RPEResiduals.swift
//  LaunchLab
//
//  Computes per-dot bearing-space residuals from:
//      • Observed bearings
//      • RS timestamps
//      • Known 3D pattern points
//      • RSPnPResult (R, t, w, v)
//
//  Output:
//      • [RPEResidual] with error.xy from bearing delta
//
//  No modification of VisionTypes.
//  Pure, deterministic, stateless.
//

import Foundation
import simd
import CoreGraphics

public final class RPEResiduals {

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------
    /// Computes bearing-space 2D residuals for each dot.
    ///
    /// - Parameters:
    ///   dots:       VisionDots (for ID only)
    ///   bearings:   observed camera-space unit rays
    ///   corrected:  RS-corrected points (timestamp included)
    ///   intrinsics: camera intrinsics (not used directly here)
    ///   pose:       RSPnPResult (R, t, w, v)
    ///   pattern3D:  known 3D pattern points
    ///
    /// - Returns:
    ///   [RPEResidual] matching input order
    ///
    public func computeResiduals(
        dots: [VisionDot],
        bearings: [RSBearing],
        corrected: [RSCorrectedPoint],
        intrinsics: CameraIntrinsics,
        pose: RSPnPResult,
        pattern3D: [SIMD3<Float>]
    ) -> [RPEResidual] {

        let n = dots.count
        guard n == bearings.count, n == corrected.count, n == pattern3D.count else {
            return []
        }

        var output: [RPEResidual] = []
        output.reserveCapacity(n)

        let R = pose.R
        let t = pose.t
        let w = pose.w
        let v = pose.v

        for i in 0..<n {

            let obs = bearings[i].ray
            let t_i = corrected[i].timestamp
            let X = pattern3D[i]

            // Current camera-space predicted point under RS motion
            let RX = R * X
            let angular = cross(w, RX) * t_i
            let linear  = v * t_i
            let Xcam = RX + t + angular + linear

            let len = simd_length(Xcam)
            if len < 1e-6 {
                // Degenerate: report zero error
                output.append(
                    RPEResidual(
                        id: dots[i].id,
                        error: SIMD2<Float>(0,0),
                        weight: 1.0
                    )
                )
                continue
            }

            let pred = Xcam / len
            let e3 = obs - pred

            // Bearing-space 2D residual = (dx, dy)
            let e2 = SIMD2<Float>(e3.x, e3.y)

            output.append(
                RPEResidual(
                    id: dots[i].id,
                    error: e2,
                    weight: 1.0
                )
            )
        }

        return output
    }
}
