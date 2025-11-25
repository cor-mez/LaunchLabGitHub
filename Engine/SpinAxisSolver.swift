//
//  SpinAxisSolver.swift
//  LaunchLab
//
//  Stage 3 — Module 12
//
//  Extracts ball spin parameters directly from RSPnPResult.w,
//  producing a SpinResult exactly as defined in VisionTypes.
//
//  Spin = angular velocity vector (rad/s) in camera coordinates.
//
//  Confidence combines:
//      • dot count
//      • timestamp spread
//      • RSPnP residual
//      • angular velocity magnitude
//
//  No modification of VisionTypes.
//
//

import Foundation
import simd
import CoreGraphics

public final class SpinAxisSolver {

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------
    /// Computes SpinResult from RSPnP SE(3) + motion estimate.
    ///
    /// - Parameters:
    ///   pose: RSPnPResult containing w (angular velocity)
    ///   corrected: RSCorrectedPoints containing timestamps
    ///   pattern3D: known 3-ring pattern (for dot count only)
    ///   intrinsics: unused, but accepted per architecture stability
    ///
    /// - Returns:
    ///   SpinResult with omega, rpm, axis, confidence
    ///
    public func solve(
        pose: RSPnPResult,
        corrected: [RSCorrectedPoint],
        pattern3D: [SIMD3<Float>],
        intrinsics: CameraIntrinsics
    ) -> SpinResult {

        // --------------------------------------------------------
        // Extract angular velocity (rad/s)
        // --------------------------------------------------------
        let w = pose.w
        let mag = simd_length(w)

        // Axis (unit), safeguard
        let axis: SIMD3<Float>
        if mag > 1e-6 {
            axis = w / mag
        } else {
            axis = SIMD3<Float>(0, 0, 1)
        }

        // rpm = |w| * 60 / (2π)
        let rpm = mag * (60.0 / (2.0 * Float.pi))

        // --------------------------------------------------------
        // Confidence metric (0–1)
        //
        // Components:
        //   A) Dot count (more dots → higher confidence)
        //   B) Timestamp span (more RS time spread → better observability)
        //   C) Motion magnitude (too tiny or huge reduces reliability)
        //   D) RSPnP residual (lower residual → higher confidence)
        //
        // Final confidence = clamp(weighted combination)
        // --------------------------------------------------------

        let dotCount = Float(pattern3D.count)

        // Normalize dot count to [0,1], assuming max ≈ 72 for 3-ring
        let cDots = min(dotCount / 72.0, 1.0)

        // Timestamp spread
        if corrected.isEmpty {
            return SpinResult(
                omega: w,
                rpm: rpm,
                axis: axis,
                confidence: 0.0
            )
        }

        let times = corrected.map { $0.timestamp }
        let tMin = times.min() ?? 0
        let tMax = times.max() ?? 0
        let tSpan = tMax - tMin

        // Normalize time span: assume useful RS range around 0.0002–0.001s
        let cTS = max(0, min(tSpan / 0.001, 1.0))

        // Angular velocity magnitude confidence
        // Ideal mid-range: 1000–8000 rpm
        // Convert rpm → normalized confidence
        let idealMin: Float = 1000
        let idealMax: Float = 8000
        let cW: Float
        if rpm < idealMin {
            cW = rpm / idealMin
        } else if rpm > idealMax {
            cW = idealMax / rpm
        } else {
            cW = 1.0
        }

        // Residual confidence (inverse map)
        // Lower residual → higher confidence
        let res = pose.residual
        let cRes = 1.0 / (1.0 + res * 2000.0)   // tuned scale factor

        // Combine
        let confidenceRaw = 0.25*cDots + 0.25*cTS + 0.25*cW + 0.25*cRes
        let confidence = max(0.0, min(confidenceRaw, 1.0))

        // --------------------------------------------------------
        // Assemble SpinResult
        // --------------------------------------------------------
        return SpinResult(
            omega: w,
            rpm: rpm,
            axis: axis,
            confidence: confidence
        )
    }
}
