//
//  BallisticsSolver.swift
//  LaunchLab
//
//  Stage 3 — Module 14
//
//  Deterministic real-time ball flight solver.
//  Uses RK2 midpoint integration, hybrid drag, and hybrid Magnus.
//  Produces BallisticsResult (frozen shared type).
//

import Foundation
import simd

public final class BallisticsSolver {

    public init() {}

    // ------------------------------------------------------------
    // MARK: - Constants
    // ------------------------------------------------------------
    private let gravity = SIMD3<Float>(0, -9.80665, 0)     // m/s²
    private let dt: Float = 0.001                          // 1 ms step
    private let maxSpeed: Float = 120.0                    // clamp (m/s)
    private let airDensity: Float = 1.225                  // kg/m³
    private let ballArea: Float = 0.001432                 // m² (golf ball)
    private let ballMass: Float = 0.04593                  // kg

    // Drag coefficient windows
    private let cdLow: Float = 0.28
    private let cdHigh: Float = 0.50

    // Magnus force scalar
    private let magnusK: Float = 0.00041

    // Ground threshold
    private let groundThreshold: Float = 0.01

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------
    public func solve(
        rspnp: RSPnPResult,
        spin: SpinResult,
        intrinsics: CameraIntrinsics
    ) -> BallisticsResult {

        // --------------------------------------------------------
        // Launch validity
        // --------------------------------------------------------
        if rspnp.isValid == false || spin.confidence < 0.1 {
            return BallisticsResult(
                apexHeight: 0,
                carryDistance: 0,
                totalDistance: 0,
                curvature: 0,
                timeOfFlight: 0,
                launchAngle: 0,
                landingAngle: 0,
                isValid: false
            )
        }

        // --------------------------------------------------------
        // Initial state
        // --------------------------------------------------------
        let v0Clamped = clampVelocity(rspnp.v)
        var v = v0Clamped
        var p = SIMD3<Float>(0, 0, 0)

        // Launch angle
        let launchAngle = atan2(v.y, length(SIMD2<Float>(v.x, v.z))) * 180 / Float.pi

        var apex: Float = 0
        var curvature: Float = 0
        var tof: Float = 0

        // Integration loop
        while true {
            // Track apex
            if p.y > apex { apex = p.y }

            // RK2 midpoint
            let a1 = acceleration(v: v, spin: spin)
            let vMid = v + a1 * (dt * 0.5)
            let a2 = acceleration(v: vMid, spin: spin)

            v += a2 * dt
            p += v * dt

            tof += dt

            // Lateral curvature
            curvature = p.x

            // Ground impact condition (Q1 = C)
            if v.y < 0 && p.y <= groundThreshold {
                break
            }

            // Safety — extremely slow or inversion
            if tof > 10 { break }
        }

        let carry = length(SIMD2<Float>(p.x, p.z))
        let landingAngle = atan2(v.y, length(SIMD2<Float>(v.x, v.z))) * 180 / Float.pi

        // Roll model (Q2 = B)
        let roll = computeRoll(carry: carry, rpm: spin.rpm)
        let total = carry + roll

        return BallisticsResult(
            apexHeight: apex,
            carryDistance: carry,
            totalDistance: total,
            curvature: curvature,
            timeOfFlight: tof,
            launchAngle: launchAngle,
            landingAngle: landingAngle,
            isValid: true
        )
    }

    // ------------------------------------------------------------
    // MARK: - Helpers
    // ------------------------------------------------------------
    private func clampVelocity(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let speed = length(v)
        if speed > maxSpeed {
            return normalize(v) * maxSpeed
        }
        return v
    }

    /// Hybrid drag + hybrid magnus
    private func acceleration(v: SIMD3<Float>, spin: SpinResult) -> SIMD3<Float> {
        let speed = max(0.1, length(v))
        let dir = v / speed

        // Hybrid Cd based on speed + spin (Q4 = D)
        let spinRatio = abs(spin.rpm) / max(1, speed * 60)
        let cd = hybridCd(speed: speed, spinRatio: spinRatio)

        let dragMag = 0.5 * airDensity * speed * speed * cd * ballArea / ballMass
        let drag = -dir * dragMag

        // Magnus (hybrid model Q3 = C)
        let magnus = magnusK * cross(spin.omega, v) / ballMass

        return gravity + drag + magnus
    }

    private func hybridCd(speed: Float, spinRatio: Float) -> Float {
        let s = min(max(speed / 70.0, 0), 1)
        let r = min(max(spinRatio / 2.0, 0), 1)
        return cdLow + (cdHigh - cdLow) * 0.5 * (s + r)
    }

    private func computeRoll(carry: Float, rpm: Float) -> Float {
        // Simple spin-based roll reduction
        let spinFactor = max(0, 1 - rpm / 8000)   // less roll at high spin
        return carry * 0.10 * spinFactor
    }
}
