//
//  TiltCorrection.swift
//  LaunchLab
//

import Foundation
import simd

/// Pure math utility for applying calibration transforms.
final class TiltCorrection {

    /// Applies roll, pitch, yaw/world alignment, and distance correction.
    func apply(
        _ rspnp: RSPnPResult,
        calibration cal: CalibrationResult?
    ) -> RSPnPResult {
        guard let cal else { return rspnp }

        // Roll/pitch
        let RP = buildRollPitchMatrix(roll: cal.roll, pitch: cal.pitch)
        var R1 = RP * rspnp.R

        // Yaw/world alignment
        R1 = cal.worldAlignmentR * R1

        // Translation
        let t1 = cal.worldAlignmentR * rspnp.t

        // Velocity
        let v1 = cal.worldAlignmentR * rspnp.v

        // Angular velocity
        let w1 = cal.worldAlignmentR * rspnp.w

        // Distance correction
        let dist = (cal.cameraToTeeDistance > 0.01)
            ? cal.cameraToTeeDistance
            : simd_length(rspnp.t)

        let tCorrected = simd_normalize(t1) * dist

        return RSPnPResult(
            R: R1,
            t: tCorrected,
            w: w1,
            v: v1,
            residual: rspnp.residual,
            isValid: rspnp.isValid
        )
    }

    /// Correct spin axis for overlay.
    func correctedSpinAxis(
        _ axis: SIMD3<Float>,
        calibration cal: CalibrationResult?
    ) -> SIMD3<Float> {
        guard let cal else { return axis }
        return simd_normalize(cal.worldAlignmentR * axis)
    }

    /// Direction angle (degrees) in world frame.
    func correctedDirectionDegrees(
        _ rspnp: RSPnPResult,
        calibration cal: CalibrationResult?
    ) -> Float {
        guard let cal else { return 0 }
        let v = simd_normalize(cal.worldAlignmentR * rspnp.v)
        return atan2(v.x, v.z) * 180 / .pi
    }

    // ------------------------------------------------------------
    // MARK: - Helpers
    // ------------------------------------------------------------

    private func buildRollPitchMatrix(
        roll: Float,
        pitch: Float
    ) -> simd_float3x3 {
        let cr = cos(roll), sr = sin(roll)
        let cp = cos(pitch), sp = sin(pitch)

        let Rroll = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cr, -sr),
            SIMD3<Float>(0, sr, cr)
        )

        let Rpitch = simd_float3x3(
            SIMD3<Float>(cp, 0, sp),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-sp, 0, cp)
        )

        return Rpitch * Rroll
    }
}
