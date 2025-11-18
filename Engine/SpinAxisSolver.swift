//
//  SpinAxisSolver.swift
//  LaunchLab
//

import Foundation
import simd

public struct SpinResult {
    public let axis: SIMD3<Float>      // unit spin axis
    public let rpm: Float              // spin rate in RPM
    public let omega: SIMD3<Float>     // raw angular velocity (rad/s)
    public let confidence: Float       // 0…1
}

public final class SpinAxisSolver {

    public init() {}

    public func solve(from rspnp: RSPnPResult?) -> SpinResult? {
        guard let r = rspnp else { return nil }

        let w = r.angularVelocity
        let mag = simd_length(w)
        if mag < 1e-6 { return nil }

        let axis = w / mag
        let rpm = mag * 60.0 / (2.0 * .pi)

        // residual uses rmsError in your RSPnPResult
        let residual = r.rmsError

        let confidenceRaw = (mag / 400.0) * (1.0 / (1.0 + residual))
        let confidence = max(0.0, min(1.0, confidenceRaw))

        return SpinResult(
            axis: axis,
            rpm: rpm,
            omega: w,
            confidence: confidence
        )
    }
}