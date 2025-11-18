//
//  RSGeometricCorrector.swift
//  LaunchLab
//
//  RS-PnP v1.5 geometric correction:
//  • Rotation correction using constant angular velocity
//  • Translation drift is computed but not applied to rays
//  • ΔT is passed through for RS-PnP v2
//

import Foundation
import simd

public struct RSCorrectedPoint {
    public let id: Int
    public let modelPoint: SIMD3<Float>
    public let correctedBearing: SIMD3<Float>
    public let deltaTranslation: SIMD3<Float>    // not applied yet
    public let timestamp: Float
}

public final class RSGeometricCorrector {

    public init() {}

    // ---------------------------------------------------------
    // Apply constant-velocity SE(3) model:
    //
    // R(t_i) = exp(ω̂ * (t_i - t0))
    // T(t_i) = T0 + v * (t_i - t0)
    //
    // We apply ΔR only to the bearing vector.
    // ΔT is passed through but NOT applied (v1.5).
    // ---------------------------------------------------------
    public func correct(
        bearings: [RSBearing],
        baseRotation: simd_quatf,
        translation: SIMD3<Float>,
        velocity: SIMD3<Float>,
        angularVelocity: SIMD3<Float>,
        baseTimestamp: Float
    ) -> [RSCorrectedPoint] {

        var out: [RSCorrectedPoint] = []
        out.reserveCapacity(bearings.count)

        for b in bearings {
            let dt = b.timestamp - baseTimestamp

            // Rotation correction
            let angle = length(angularVelocity * dt)
            let axis: SIMD3<Float> =
                angle > 0 ? normalize(angularVelocity) : SIMD3<Float>(0,1,0)

            let dR = simd_quatf(angle: angle, axis: axis)
            let R_total = baseRotation * dR

            let corrected = normalize(R_total.act(b.bearing))

            // Translation drift calculated but not applied (v1.5)
            let dT = velocity * dt

            out.append(
                RSCorrectedPoint(
                    id: b.id,
                    modelPoint: b.modelPoint,
                    correctedBearing: corrected,
                    deltaTranslation: dT,
                    timestamp: b.timestamp
                )
            )
        }

        return out
    }
}