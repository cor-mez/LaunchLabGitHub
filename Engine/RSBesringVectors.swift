//
//  RSBearingVectors.swift
//  LaunchLab
//

import Foundation
import simd

// ============================================================
// MARK: - Bearing Struct
// ============================================================

public struct RSBearing {
    public let id: Int                // dot ID (0…71)
    public let modelPoint: SIMD3<Float>
    public let bearing: SIMD3<Float>  // normalized camera ray
    public let timestamp: Float       // per-dot RS time offset
}


// ============================================================
// MARK: - Bearing Vector Generator
// ============================================================

public final class RSBearingVectors {

    // ---------------------------------------------------------
    // MARK: - Compute
    // ---------------------------------------------------------
    public func compute(
        imagePoints: [SIMD2<Float>],
        modelPoints: [SIMD3<Float>],
        timestamps: [Float],
        intrinsics K: simd_float3x3
    ) -> [RSBearing] {

        let count = min(imagePoints.count, modelPoints.count, timestamps.count)
        if count == 0 { return [] }

        var out = [RSBearing]()
        out.reserveCapacity(count)

        // Extract intrinsics
        let fx = K[0,0]
        let fy = K[1,1]
        let cx = K[0,2]
        let cy = K[1,2]

        // -----------------------------------------------------
        // Convert each pixel → normalized pinhole ray
        // -----------------------------------------------------
        for i in 0..<count {

            let p = imagePoints[i]
            let Xw = modelPoints[i]
            let t = timestamps[i]

            // Pixel → normalized camera ray
            let x = (p.x - cx) / fx
            let y = (p.y - cy) / fy
            let z: Float = 1.0

            var ray = SIMD3<Float>(x, y, z)
            let invLen = 1.0 / simd_length(ray)
            ray *= invLen

            // Append
            out.append(
                RSBearing(
                    id: i,
                    modelPoint: Xw,
                    bearing: ray,
                    timestamp: t
                )
            )
        }

        return out
    }
}