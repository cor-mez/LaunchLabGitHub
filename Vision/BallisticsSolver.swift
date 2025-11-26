//
//  BallisticsSolver.swift
//  LaunchLab
//
//  Ballistics V1 -- Full Launch Monitor Output
//
//  Inputs:
//    - RSPnPResult (position + unit velocity direction)
//    - SpinResult (spin axis + spinRPM)
//    - Optional: estimated speed magnitude from velocity delta
//
//  Outputs:
//    - Full launch monitor metrics (GCQuad-style)
//
//  Notes:
//    - Uses Euler integration for simple V1 flight simulation
//    - Drag model: Cd ~ 0.22–0.30 depending on spin
//    - Lift model: CL = k * spin (radians/s) * velocity
//

import Foundation
import simd

public struct BallisticsResult {
    public let speedMps: Float
    public let launchAngleDeg: Float
    public let azimuthDeg: Float
    public let spinRPM: Float
    public let spinAxis: SIMD3<Float>
    public let liftCoeff: Float
    public let dragCoeff: Float
    public let carry: Float
    public let apex: Float
    public let timeOfFlight: Float
    public let landingAngle: Float
}

public final class BallisticsSolver {

    public init() {}

    // -------------------------------------------------------------------------
    // MARK: - Entry
    // -------------------------------------------------------------------------

    /// Compute full launch-ballistic solution.
    public func solve(
        rspnp: RSPnPResult,
        spin: SpinResult
    ) -> BallisticsResult? {

        let dir = rspnp.velocity
        if simd_length(dir) < 1e-6 { return nil }

        // Approx launch speed magnitude.
        // V1: Assume spacing between frames (~3 frames @240fps) is small,
        // so we use a nominal speed of 65 m/s ± direction/SNR adjustments.
        // A better magnitude estimator will come in RS-PnP V2.
        let nominalSpeed: Float = estimateSpeedMagnitude(
            rspnp: rspnp,
            spin: spin
        )

        // Extract angles
        let launchAngleDeg = radiansToDegrees(atan2f(dir.z, hypotf(dir.x, dir.y)))
        let azimuthDeg = radiansToDegrees(atan2f(dir.y, dir.x))

        // Spin RPM
        let spinRPM = spin.spinRPM
        let spinAxis = simd_normalize(spin.spinAxis)

        // Aerodynamic coefficients
        let Cd = estimateDragCoeff(speed: nominalSpeed, spinRPM: spinRPM)
        let Cl = estimateLiftCoeff(speed: nominalSpeed, spinRPM: spinRPM)

        // Run simplified flight simulation
        let (carry, apex, tof, landingAngle) = simulateFlight(
            speed: nominalSpeed,
            direction: dir,
            spinAxis: spinAxis,
            spinRPM: spinRPM,
            Cd: Cd,
            Cl: Cl
        )

        return BallisticsResult(
            speedMps: nominalSpeed,
            launchAngleDeg: launchAngleDeg,
            azimuthDeg: azimuthDeg,
            spinRPM: spinRPM,
            spinAxis: spinAxis,
            liftCoeff: Cl,
            dragCoeff: Cd,
            carry: carry,
            apex: apex,
            timeOfFlight: tof,
            landingAngle: landingAngle
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Speed magnitude estimation (V1)
    // -------------------------------------------------------------------------

    /// V1 approximation:
    /// - Typical amateur swing speeds: 35–70 m/s
    /// - Use spin axis / consistency to bias magnitude a bit
    private func estimateSpeedMagnitude(
        rspnp: RSPnPResult,
        spin: SpinResult
    ) -> Float {
        // Start with a neutral default
        var speed: Float = 60.0

        // If rotation axis is strong & stable, bump speed
        if spin.confidence > 0.7, spin.spinRPM > 3000 {
            speed = 65.0
        }

        if spin.confidence < 0.3, spin.spinRPM < 1500 {
            speed = 50.0
        }

        return speed
    }

    // -------------------------------------------------------------------------
    // MARK: - Aerodynamic coefficients
    // -------------------------------------------------------------------------

    /// Drag coefficient (roughly 0.20–0.30)
    private func estimateDragCoeff(speed: Float, spinRPM: Float) -> Float {
        // Spin increases drag slightly.
        let base: Float = 0.22
        let spinTerm = min(0.08, spinRPM / 8000.0)
        return base + spinTerm
    }

    /// Lift coefficient from spin (rough TrackMan model)
    private func estimateLiftCoeff(speed: Float, spinRPM: Float) -> Float {
        // Convert RPM → rad/s
        let omega = spinRPM * (2 * Float.pi / 60.0)
        // Simple proportional lift model
        return min(0.3, 0.00005 * omega)
    }

    // -------------------------------------------------------------------------
    // MARK: - Flight simulation (Euler)
    // -------------------------------------------------------------------------

    private func simulateFlight(
        speed: Float,
        direction: SIMD3<Float>,
        spinAxis: SIMD3<Float>,
        spinRPM: Float,
        Cd: Float,
        Cl: Float
    ) -> (carry: Float, apex: Float, time: Float, landingAngle: Float) {

        let g: Float = 9.81
        let dt: Float = 0.005   // simulation timestep

        // State
        var pos = SIMD3<Float>(0, 0, 0)   // origin = impact point
        var vel = direction * speed

        var maxZ: Float = 0
        var time: Float = 0

        // Spin vector (rad/s)
        let omega = spinRPM * (2 * .pi / 60)
        let spinVec = spinAxis * omega

        // Integration loop
        while pos.z >= 0 {
            time += dt

            // Gravity
            let Fg = SIMD3<Float>(0, 0, -g)

            // Drag: Fd = -Cd * v^2 * v̂
            let v = vel
            let vMag = simd_length(v)
            let vHat = v / max(vMag, 1e-6)
            let Fd = -Cd * vMag * vMag * vHat

            // Lift: Fl = Cl * (ω × v)
            let Fl = Cl * simd_cross(spinVec, v)

            // Acceleration
            let acc = Fg + Fd + Fl

            // Euler integration
            vel += acc * dt
            pos += vel * dt

            // Apex
            if pos.z > maxZ { maxZ = pos.z }

            // Safety break
            if time > 12 { break }
        }

        // Landing angle = angle between velocity vector and ground plane
        let landingAngle = radiansToDegrees(atan2f(-vel.z, hypotf(vel.x, vel.y)))

        return (pos.x, maxZ, time, landingAngle)
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private func radiansToDegrees(_ r: Float) -> Float {
        return r * 180.0 / .pi
    }
}