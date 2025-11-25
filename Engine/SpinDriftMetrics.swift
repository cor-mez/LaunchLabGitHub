//
//  SpinDriftMetrics.swift
//  LaunchLab
//
//  Stage 3 — Module 13
//
//  Computes frame-to-frame spin-axis stability using:
//      • angular drift (deg/frame)
//      • spin confidences
//      • rpm-based weighting
//
//  Output:
//      SpinDriftMetrics (frozen VisionTypes)
//
//  Pure, deterministic, stateless.
//

import Foundation
import simd

public final class SpinDriftMetricsSolver {

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------
    /// Computes spin drift metrics between two consecutive spin results.
    ///
    /// - Parameters:
    ///   current:  SpinResult for the current frame
    ///   previous: SpinResult for the previous frame, if any
    ///
    /// - Returns:
    ///   SpinDriftMetrics (deltaAxis, driftRate, stability)
    ///
    public func compute(
        current: SpinResult,
        previous: SpinResult?
    ) -> SpinDriftMetrics {

        // --------------------------------------------------------
        // Case 1 — No previous frame
        // --------------------------------------------------------
        guard let prev = previous else {
            return SpinDriftMetrics(
                deltaAxis: SIMD3<Float>(0, 0, 0),
                driftRate: 0.0,
                stability: current.confidence     // Per contract Q1: A
            )
        }

        let a = current.axis
        let b = prev.axis

        // --------------------------------------------------------
        // Delta axis
        // --------------------------------------------------------
        let deltaAxis = a - b

        // --------------------------------------------------------
        // Angular drift rate (deg/frame)
        // --------------------------------------------------------
        let dotAB = max(-1.0, min(1.0, dot(a, b)))
        let theta = acos(dotAB)     // radians
        let driftDeg = theta * 180.0 / Float.pi

        // --------------------------------------------------------
        // Composite Stability Metric (Q2: C)
        //
        // stability = (c_prev * c_curr) * exp(-k*drift) * f(rpm)
        //
        // Components:
        //   c_prev, c_curr   → spin confidence values
        //   exp(-k*drift)    → exponential decay w.r.t drift in degrees
        //   f(rpm)           → validity boost for reasonable spin rates
        //
        // rpm model:
        //   - below 500 rpm → penalize
        //   - 500–10000 rpm → ideal range
        //   - above 10000   → penalize
        //
        // --------------------------------------------------------

        let cPrev = prev.confidence
        let cCurr = current.confidence

        // Drift decay coefficient
        let k: Float = 0.08    // tuned for degrees-per-frame input
        let driftWeight = exp(-k * driftDeg)

        // RPM weighting function
        let rpm = current.rpm
        let fRPM: Float
        if rpm < 500 {
            fRPM = rpm / 500.0                 // 0→1
        } else if rpm > 10000 {
            fRPM = 10000.0 / rpm               // decays above max
        } else {
            fRPM = 1.0                          // ideal range
        }

        let stabilityRaw = (cPrev * cCurr) * driftWeight * fRPM
        let stability = max(0.0, min(stabilityRaw, 1.0))

        return SpinDriftMetrics(
            deltaAxis: deltaAxis,
            driftRate: driftDeg,
            stability: stability
        )
    }
}
