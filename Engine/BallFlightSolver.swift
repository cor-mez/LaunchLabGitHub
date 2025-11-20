//
//  BallFlightSolver.swift
//  LaunchLab
//

import Foundation
import simd

// ============================================================
// MARK: - BallFlightSolver
// ============================================================

public enum BallFlightSolver {

    // ========================================================
    // MARK: Public Entry Point
    // ========================================================
    public static func solve(
        position: SIMD3<Float>?,        // from RS-PnP.T  (meters, camera frame)
        velocity: SIMD3<Float>?,        // from VelocityTracker or finite diff
        spin: SpinResult?               // from SpinAxisSolver
    ) -> BallFlightResult? {

        guard
            let pos0 = position,
            let v0   = velocity,
            let spin = spin
        else {
            return nil
        }

        // Build aerodynamic model
        let model = BallFlightModel(
            velocity: v0,
            spinAxis: spin.axis,
            rpm: spin.rpm
        )

        // Integrate trajectory
        let solver = BallisticsSolver(model: model)
        let result = solver.integrate(initialPosition: pos0)

        return result
    }
}

// ============================================================
// MARK: - BallFlightModel
// ============================================================

public struct BallFlightModel {

    // --------------------------------------------------------
    // Physical constants
    // --------------------------------------------------------
    public let mass: Float           = 0.04593        // kg
    public let radius: Float         = 0.02135        // m
    public let area: Float           = 0.001433       // m^2  (πr²)
    public let rho_air: Float        = 1.225          // kg/m³
    public let Cd: Float             = 0.25           // drag coefficient
    public let g: SIMD3<Float>       = SIMD3<Float>(0, -9.80665, 0)

    // --------------------------------------------------------
    // Inputs
    // --------------------------------------------------------
    public var velocity: SIMD3<Float>
    public var spinAxis: SIMD3<Float>      // unit vector
    public var rpm: Float                  // spin rate

    // --------------------------------------------------------
    // MARK: Lift Coefficient (Cl)
    // --------------------------------------------------------
    @inline(__always)
    public func liftCoefficient() -> Float {
        // Smits & Smith empirical fit
        let x = rpm
        let cl = 0.000533 * x - 0.000002 * x * x + 0.15
        return max(0, min(cl, 1.8))
    }

    // --------------------------------------------------------
    // MARK: Spin Decay
    // --------------------------------------------------------
    @inline(__always)
    public func spinDecay(t: Float) -> Float {
        // exponential decay model
        let k_spin: Float = 1.5
        return rpm * exp(-k_spin * t)
    }

    // --------------------------------------------------------
    // MARK: Aerodynamic Forces
    // --------------------------------------------------------
    @inline(__always)
    public func forces(velocity v: SIMD3<Float>, time t: Float) -> SIMD3<Float> {

        let speed = simd_length(v)
        if speed < 0.1 {
            return g
        }

        let vNorm = v / speed

        // Drag
        let Fd = -0.5 * rho_air * Cd * area * speed * speed * vNorm

        // Lift
        let Cl = liftCoefficient()
        let axis = spinAxis
        let liftDir = simd_normalize(simd_cross(axis, vNorm))
        let Fl = 0.5 * rho_air * Cl * area * speed * speed * liftDir

        // Total acceleration
        return (Fd + Fl) / mass + g
    }
}

// ============================================================
// MARK: - BallisticsSolver (RK4)
// ============================================================

public final class BallisticsSolver {

    private let model: BallFlightModel
    private let dt: Float = 0.001        // 1 ms integration

    public init(model: BallFlightModel) {
        self.model = model
    }

    // --------------------------------------------------------
    // MARK: Integrate Until Impact
    // --------------------------------------------------------
    public func integrate(initialPosition p0: SIMD3<Float>) -> BallFlightResult {

        var p = p0
        var v = model.velocity

        var trajectory: [SIMD3<Float>] = []
        trajectory.reserveCapacity(8000)   // up to ~8 seconds @ 1ms

        var t: Float = 0
        var apex: Float = p.y

        let spinAxis = model.spinAxis
        let rpm = model.rpm

        // Integrate until ball hits ground (y <= 0)
        while p.y > 0 && t < 10 {

            trajectory.append(p)

            // Record apex
            apex = max(apex, p.y)

            // RK4 integration
            let a1 = model.forces(velocity: v, time: t)
            let v1 = v
            let p1 = p

            let a2 = model.forces(velocity: v + 0.5 * dt * a1, time: t + 0.5 * dt)
            let v2 = v + 0.5 * dt * a1
            let p2 = p + 0.5 * dt * v1

            let a3 = model.forces(velocity: v + 0.5 * dt * a2, time: t + 0.5 * dt)
            let v3 = v + 0.5 * dt * a2
            let p3 = p + 0.5 * dt * v2

            let a4 = model.forces(velocity: v + dt * a3, time: t + dt)
            let v4 = v + dt * a3
            let p4 = p + dt * v3

            v = v + (dt / 6.0) * (a1 + 2*a2 + 2*a3 + a4)
            p = p + (dt / 6.0) * (v1 + 2*v2 + 2*v3 + v4)

            t += dt
        }

        let carry = p.x
        let landingAngle = atan2(v.y, simd_length(SIMD2<Float>(v.x, v.z)))
        let sideCurve = finalSideCurve(trajectory)

        return BallFlightResult(
            carryDistance: carry,
            apexHeight: apex,
            landingAngle: landingAngle,
            sideCurve: sideCurve,
            duration: t,
            trajectory: trajectory,
            initialVelocity: model.velocity,
            spinAxis: spinAxis,
            rpm: rpm
        )
    }
}
// ============================================================
// MARK: - Side Curve Calculation
// ============================================================

private extension BallisticsSolver {

    /// Compute left/right curvature from the trajectory.
    /// Positive = curve right (fade), Negative = curve left (draw).
    ///
    /// This measures lateral deflection relative to the initial direction.
    @inline(__always)
    func finalSideCurve(_ traj: [SIMD3<Float>]) -> Float {
        guard traj.count > 4 else { return 0 }

        let start = traj[0]
        let end   = traj[traj.count - 1]

        // Lateral displacement in Z-axis
        return end.z - start.z
    }
}

// ============================================================
// MARK: - BallFlightResult
// ============================================================

public struct BallFlightResult {

    /// Horizontal carry distance (meters)
    public let carryDistance: Float

    /// Max height (meters)
    public let apexHeight: Float

    /// Landing angle (radians)
    public let landingAngle: Float

    /// Total side curve (meters)
    public let sideCurve: Float

    /// Total flight duration (seconds)
    public let duration: Float

    /// Full 3D trajectory (meters)
    public let trajectory: [SIMD3<Float>]

    /// Initial velocity (m/s)
    public let initialVelocity: SIMD3<Float>

    /// Spin axis used during flight
    public let spinAxis: SIMD3<Float>

    /// Spin rate (RPM)
    public let rpm: Float
}