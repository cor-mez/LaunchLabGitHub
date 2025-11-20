//
//  BallFlightModel.swift
//  LaunchLab
//

import Foundation
import simd

/// High-fidelity aerodynamic model for golf ball flight.
/// Computes instantaneous acceleration from drag, lift (Magnus),
/// gravity, and spin decay.
///
/// Inputs:
///   • velocity: 3D velocity vector (m/s)
///   • spinAxis: unit vector from SpinAxisSolver
///   • rpm: initial spin rate (rev/min)
///   • t: elapsed time (s)
///
/// Output:
///   • acceleration: SIMD3<Float>
///
/// This model is called repeatedly by BallisticsSolver (RK4).
public enum BallFlightModel {

    // ============================================================
    // MARK: - Physical Constants
    // ============================================================

    // Mass of golf ball
    private static let mass: Float = 0.04593

    // Radius of golf ball (meters)
    private static let radius: Float = 0.02135

    // Cross-sectional area πr²
    private static let area: Float = .pi * radius * radius

    // Air density (kg/m^3)
    private static let rho_air: Float = 1.225

    // Drag coefficient (typical mid-flight value)
    private static let Cd: Float = 0.25

    // Spin decay constant (1/s)
    private static let k_spin: Float = 1.5

    // Gravity vector (m/s^2)
    private static let gravity = SIMD3<Float>(0, -9.80665, 0)

    // ============================================================
    // MARK: - Public API
    // ============================================================

    /// Compute aerodynamic + gravitational acceleration.
    ///
    /// - Parameters:
    ///   - velocity: instantaneous velocity (m/s)
    ///   - spinAxis: unit vector (SpinAxisSolver)
    ///   - rpm0: initial spin rate at t=0
    ///   - t: elapsed time (seconds)
    ///
    /// - Returns: acceleration (m/s^2)
    public static func acceleration(
        velocity v: SIMD3<Float>,
        spinAxis: SIMD3<Float>,
        rpm0: Float,
        time t: Float
    ) -> SIMD3<Float> {

        let speed = simd_length(v)
        if speed < 0.01 {
            return gravity
        }

        // --------------------------------------------------------
        // 1. Unit velocity
        // --------------------------------------------------------
        let vHat = v / speed

        // --------------------------------------------------------
        // 2. Drag force
        //    Fd = 0.5 * rho * Cd * A * v^2 * (-vHat)
        // --------------------------------------------------------
        let dragMag = 0.5 * rho_air * Cd * area * (speed * speed)
        let Fd = -dragMag * vHat

        // --------------------------------------------------------
        // 3. Spin decay
        //    omega(t) = omega0 * exp(-k*t)
        //    rpm → rad/s:  rpm * 2π / 60
        // --------------------------------------------------------
        let omega0 = rpm0 * (2 * Float.pi / 60)
        let omega = omega0 * exp(-k_spin * t)

        // Convert back to rpm for lift coefficient model
        let rpm_t = omega * (60 / (2 * .pi))

        // --------------------------------------------------------
        // 4. Lift coefficient Cl(rpm)
        //    Smits & Smith empirical model
        // --------------------------------------------------------
        var Cl = 0.000533 * rpm_t - 0.000002 * rpm_t * rpm_t + 0.15
        Cl = max(0, min(1.8, Cl))

        // --------------------------------------------------------
        // 5. Magnus (lift) force
        //    Fl = 0.5 * rho * Cl * A * v^2 * (spinAxis × vHat)
        // --------------------------------------------------------
        let liftDirRaw = simd_cross(spinAxis, vHat)
        let liftDirLen = simd_length(liftDirRaw)

        let liftDir = liftDirLen > 0.0001
            ? liftDirRaw / liftDirLen
            : SIMD3<Float>(0,0,0)

        let liftMag = 0.5 * rho_air * Cl * area * (speed * speed)
        let Fl = liftMag * liftDir

        // --------------------------------------------------------
        // 6. Net force → acceleration
        // --------------------------------------------------------
        let Fnet = Fd + Fl + mass * gravity
        return Fnet / mass
    }
}