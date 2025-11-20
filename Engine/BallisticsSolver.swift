//
//  BallisticsSolver.swift
//  LaunchLab
//

import Foundation
import simd

/// Numerical ballistics integrator for golf ball flight.
/// Uses RK4 with dt = 1 ms for high-accuracy trajectory.
///
/// Inputs:
///   • initialPosition: ball origin in camera / world coords
///   • initialVelocity: launch velocity (m/s)
///   • spinAxis: unit vector (SpinAxisSolver)
///   • rpm: initial spin rate
///
/// Produces:
///   • full trajectory
///   • carry distance
///   • apex height
///   • landing angle
///   • total flight time
public enum BallisticsSolver {

    // 1 ms integration step
    private static let dt: Float = 0.001

    // Maximum steps (~10 seconds max flight)
    private static let maxSteps = 12_000

    // Small epsilon for ground detection
    private static let groundEps: Float = 0.001

    // ============================================================
    // MARK: - Public API
    // ============================================================

    public static func solve(
        initialPosition p0: SIMD3<Float>,
        initialVelocity v0: SIMD3<Float>,
        spinAxis: SIMD3<Float>,
        rpm: Float
    ) -> BallFlightResult {

        var pos = p0
        var vel = v0

        var trajectory = [SIMD3<Float>]()
        trajectory.reserveCapacity(2000)
        trajectory.append(pos)

        var apexHeight: Float = pos.y
        var time: Float = 0

        // RK4 integration loop
        for _ in 0..<maxSteps {

            // Record apex
            if pos.y > apexHeight { apexHeight = pos.y }

            // Ground impact stop
            if pos.y <= groundEps && time > 0.05 {
                break
            }

            let (pNext, vNext) = rk4Step(
                position: pos,
                velocity: vel,
                spinAxis: spinAxis,
                rpm: rpm,
                time: time
            )

            pos = pNext
            vel = vNext
            time += dt

            trajectory.append(pos)
        }

        // Compute carry distance (horizontal)
        let carry = horizontalDistance(from: p0, to: pos)

        // Landing angle (angle between velocity and horizontal)
        let landingAngle = landingAngleDeg(vel)

        // Side curvature from trajectory
        let sideCurve = computeSideCurve(trajectory)

        return BallFlightResult(
            carryDistance: carry,
            apexHeight: apexHeight,
            landingAngleDeg: landingAngle,
            sideCurve: sideCurve,
            totalTime: time,
            trajectory: trajectory,
            initialVelocity: v0,
            spinAxis: spinAxis,
            rpm: rpm
        )
    }

    // ============================================================
    // MARK: - RK4 Step
    // ============================================================

    private static func rk4Step(
        position p: SIMD3<Float>,
        velocity v: SIMD3<Float>,
        spinAxis: SIMD3<Float>,
        rpm: Float,
        time t: Float
    ) -> (SIMD3<Float>, SIMD3<Float>) {

        let h = dt

        // k1
        let a1 = BallFlightModel.acceleration(
            velocity: v, spinAxis: spinAxis, rpm0: rpm, time: t
        )
        let k1p = v
        let k1v = a1

        // k2
        let v2 = v + 0.5*h*k1v
        let a2 = BallFlightModel.acceleration(
            velocity: v2, spinAxis: spinAxis, rpm0: rpm, time: t + 0.5*h
        )
        let k2p = v2
        let k2v = a2

        // k3
        let v3 = v + 0.5*h*k2v
        let a3 = BallFlightModel.acceleration(
            velocity: v3, spinAxis: spinAxis, rpm0: rpm, time: t + 0.5*h
        )
        let k3p = v3
        let k3v = a3

        // k4
        let v4 = v + h*k3v
        let a4 = BallFlightModel.acceleration(
            velocity: v4, spinAxis: spinAxis, rpm0: rpm, time: t + h
        )
        let k4p = v4
        let k4v = a4

        // Aggregate
        let pNext = p + (h/6) * (k1p + 2*k2p + 2*k3p + k4p)
        let vNext = v + (h/6) * (k1v + 2*k2v + 2*k3v + k4v)

        return (pNext, vNext)
    }

    // ============================================================
    // MARK: - Utility Functions
    // ============================================================

    @inline(__always)
    private static func horizontalDistance(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x
        let dz = b.z - a.z
        return sqrt(dx*dx + dz*dz)
    }

    @inline(__always)
    private static func landingAngleDeg(_ v: SIMD3<Float>) -> Float {
        let horiz = sqrt(v.x*v.x + v.z*v.z)
        let angle = atan2(v.y, horiz)
        return angle * 180.0 / .pi
    }

    @inline(__always)
    private static func computeSideCurve(_ traj: [SIMD3<Float>]) -> Float {
        guard let first = traj.first else { return 0 }
        var maxLateral: Float = 0
        for p in traj {
            let lateral = abs(p.x - first.x)
            if lateral > maxLateral { maxLateral = lateral }
        }
        return maxLateral
    }
}