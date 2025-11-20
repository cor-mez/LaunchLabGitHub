//
//  SpinDriftMetrics.swift
//  LaunchLab
//

import Foundation
import simd

/// Compact, allocation-free, pure SIMD metrics for measuring
/// frame-to-frame spin drift.
///
/// Computed immediately after SpinAxisSolver produces a new SpinResult.
public struct SpinDriftMetrics {

    // ============================================================
    // MARK: - Public Fields
    // ============================================================

    /// Degrees between previous axis and current axis.
    public let axisDriftDeg: Float

    /// Absolute change in |ω| magnitude from last frame.
    public let omegaDrift: Float

    /// 0…1 combined stability (1 = perfectly stable).
    public let stabilityScore: Float

    /// True if axis drift is large enough to flag wobble.
    public let wobbleFlag: Bool


    // ============================================================
    // MARK: - Static Zero
    // ============================================================

    /// Neutral "no data" metrics -- used when prev or current SpinResult is nil.
    public static let zero = SpinDriftMetrics(
        axisDriftDeg: 0,
        omegaDrift: 0,
        stabilityScore: 0,
        wobbleFlag: false
    )


    // ============================================================
    // MARK: - Initializer
    // ============================================================

    /// Main initializer for VisionPipeline.
    ///
    /// Rules:
    /// • If prev or curr missing → return .zero  
    /// • axis drift computed from angle between unit vectors  
    /// • omega drift = | |ω₂| – |ω₁| |  
    /// • stabilityScore = equal blend of axis & magnitude stability  
    /// • wobbleFlag = axis drift ≥ 5°
    public init(previous: SpinResult?, current: SpinResult?) {

        guard
            let p = previous,
            let c = current
        else {
            self = .zero
            return
        }

        // --------------------------------------------------------
        // 1. Axis Drift (degrees)
        // --------------------------------------------------------
        let dotVal = max(-1.0, min(1.0, simd_dot(p.axis, c.axis)))
        let angleRad = acos(dotVal)
        let angleDeg = angleRad * 180.0 / .pi
        let axisDrift = angleDeg

        // --------------------------------------------------------
        // 2. Omega Drift (magnitude change)
        // --------------------------------------------------------
        let magPrev = simd_length(p.omega)
        let magCurr = simd_length(c.omega)
        let omegaDrift = abs(magCurr - magPrev)

        // --------------------------------------------------------
        // 3. Stability Score
        // --------------------------------------------------------
        //
        // Axis stability: 1.0 for 0°, 0.0 for ≥10°
        let axisStability = max(0.0, min(1.0, 1.0 - (axisDrift / 10.0)))

        // Magnitude stability: 1.0 for Δω=0, 0.0 for Δω≥200 rad/s
        let magStability = max(0.0, min(1.0, 1.0 - (omegaDrift / 200.0)))

        // equal weighting
        let stabilityScore = 0.5 * (axisStability + magStability)

        // --------------------------------------------------------
        // 4. Wobble Flag
        // --------------------------------------------------------
        let wobble = axisDrift >= 5.0

        self.axisDriftDeg = axisDrift
        self.omegaDrift = omegaDrift
        self.stabilityScore = stabilityScore
        self.wobbleFlag = wobble
    }
}