//
//  RSGeometricCorrector.swift
//  LaunchLab
//

import Foundation
import simd

// ============================================================
// MARK: - Corrected RS Point
// ============================================================

public struct RSCorrectedPoint {
    public let id: Int
    public let modelPoint: SIMD3<Float>
    public let correctedBearing: SIMD3<Float>   // after linear RS correction
    public let timestamp: Float                 // Δt relative to frame start
}


// ============================================================
// MARK: - Linear RS Geometric Corrector (v1.5)
// ============================================================

public final class RSGeometricCorrector {

    // ---------------------------------------------------------
    // MARK: - Correct
    // ---------------------------------------------------------
    //
    // Applies:
    //
    //   Xc(t) ≈ R0ᵀ * model
    //          + (ω × Xc) * Δt
    //          + v * Δt
    //
    // Then converts Xc(t) → normalized corrected bearing.
    //
    public func correct(
        bearings: [RSBearing],
        baseRotation R0: simd_quatf,
        translation T0: SIMD3<Float>,
        velocity v: SIMD3<Float>,
        angularVelocity w: SIMD3<Float>,
        baseTimestamp: Float
    ) -> [RSCorrectedPoint] {

        if bearings.isEmpty { return [] }

        var out: [RSCorrectedPoint] = []
        out.reserveCapacity(bearings.count)

        let R0mat = R0.act // convert quaternion → rotation

        for b in bearings {

            let id = b.id
            let t = b.timestamp - baseTimestamp   // Δt for rolling shutter

            // --------------------------------------------
            // 1. Base camera-space 3D point
            //     Xc0 = R0 * Xmodel + T0
            // --------------------------------------------
            let Xc0 = R0mat * b.modelPoint + T0

            // --------------------------------------------
            // 2. Linearized RS motion
            // --------------------------------------------
            // Angular term: ω × Xc0
            let cross = simd_cross(w, Xc0)

            // Linear update:
            //   Xc(t) = Xc0 + cross*t + v*t
            let Xt = Xc0 + cross * t + v * t

            // --------------------------------------------
            // 3. Convert corrected 3D point to bearing
            // --------------------------------------------
            var ray = Xt
            let invLen = 1.0 / simd_length(ray)
            ray *= invLen

            // --------------------------------------------
            // 4. Append
            // --------------------------------------------
            out.append(
                RSCorrectedPoint(
                    id: id,
                    modelPoint: b.modelPoint,
                    correctedBearing: ray,
                    timestamp: t
                )
            )
        }

        return out
    }
}

private extension simd_quatf {
    @inline(__always)
    var act: simd_float3x3 {
        return simd_float3x3(self)
    }
}