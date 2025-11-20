//
//  BallFlightResult.swift
//  LaunchLab
//

import Foundation
import simd

/// Complete physical outcome of a simulated golf ball flight.
///
/// Produced by BallisticsSolver.solve(), then attached to VisionFrameData.
///
/// All units in SI unless otherwise noted:
///   • distances: meters
///   • angles: degrees
///   • time: seconds
///   • velocity: m/s
///   • spin: rpm
public struct BallFlightResult {

    // ============================================================
    // MARK: - Primary Flight Metrics
    // ============================================================

    /// Horizontal carry distance (from launch to ground impact).
    public let carryDistance: Float

    /// Highest vertical point reached during trajectory (meters).
    public let apexHeight: Float

    /// Angle of descent at impact (degrees).
    public let landingAngleDeg: Float

    /// Maximum lateral deviation from launch line (meters).
    public let sideCurve: Float

    /// Total flight duration until ground impact (seconds).
    public let totalTime: Float


    // ============================================================
    // MARK: - Trajectory + Initial Conditions
    // ============================================================

    /// Full polyline of simulated positions over time.
    public let trajectory: [SIMD3<Float>]

    /// Launch velocity vector (m/s).
    public let initialVelocity: SIMD3<Float>

    /// Spin axis (unit vector, camera/world space).
    public let spinAxis: SIMD3<Float>

    /// Initial spin rate (rpm).
    public let rpm: Float


    // ============================================================
    // MARK: - Zero / Placeholder
    // ============================================================

    public static let zero = BallFlightResult(
        carryDistance: 0,
        apexHeight: 0,
        landingAngleDeg: 0,
        sideCurve: 0,
        totalTime: 0,
        trajectory: [],
        initialVelocity: SIMD3(0,0,0),
        spinAxis: SIMD3(0,1,0),
        rpm: 0
    )
}