//
//  VisionTypes.swift
//  LaunchLab
//
//  Frozen Architecture — v1.1
//  This file defines ALL cross-module data contracts.
//  No other file may declare duplicate structs.
//
//  All downstream modules (RS, PnP, Spin, Ballistics, KLT, Overlays)
//  MUST conform exactly to these definitions.
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

// ============================================================
// MARK: - Camera Intrinsics
// ============================================================

/// Pixel-space intrinsics for a single iOS camera calibration.
/// Frozen contract: used across RS bearings, PnP, overlays.
public struct CameraIntrinsics: Sendable {

    public let fx: Float
    public let fy: Float
    public let cx: Float
    public let cy: Float
    public let K: simd_float3x3
    public let Kinv: simd_float3x3

    public init(fx: Float, fy: Float, cx: Float, cy: Float) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy

        self.K = simd_float3x3(rows: [
            SIMD3(fx,    0,   cx),
            SIMD3( 0,   fy,   cy),
            SIMD3( 0,    0,    1)
        ])

        self.Kinv = self.K.inverse
    }

    /// Zero intrinsics placeholder (never used in production)
    public static let zero = CameraIntrinsics(fx: 1, fy: 1, cx: 0, cy: 0)
}

// ============================================================
// MARK: - Vision Dot
// ============================================================

/// A single dot tracked on the ball. Stable across frames.
/// Assigned by DotTracker → used by LK → Pose → Spin.
public struct VisionDot: Identifiable, Sendable {
    public let id: Int
    public let position: CGPoint
    public let predicted: CGPoint?
    public let velocity: CGVector?

    public init(id: Int,
                position: CGPoint,
                predicted: CGPoint? = nil,
                velocity: CGVector? = nil) {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.velocity = velocity
    }
}

// ============================================================
// MARK: - Tracking State
// ============================================================

public enum DotTrackingState: Sendable {
    case initial       // no history yet
    case tracking      // stable LK + ID association
    case lost          // insufficient correspondences
}

// ============================================================
// MARK: - Rolling-Shutter Bearing
// ============================================================

/// A unit ray representing a pixel’s direction in camera coordinates.
/// rowIndex → used to compute timestamp relative to shutter scan.
public struct RSBearing: Sendable {
    public let ray: SIMD3<Float>     // unit 3D bearing
    public let rowIndex: Int         // pixel row for RS timing

    public init(ray: SIMD3<Float>, rowIndex: Int) {
        self.ray = ray
        self.rowIndex = rowIndex
    }
}

// ============================================================
// MARK: - RS-Corrected Pixel
// ============================================================

/// Pixel after RS unwarp. Used for RS-PnP and overlays.
public struct RSCorrectedPoint: Sendable {
    public let original: CGPoint
    public let corrected: CGPoint
    public let timestamp: Float       // time derived from RS line index

    public init(original: CGPoint,
                corrected: CGPoint,
                timestamp: Float) {
        self.original = original
        self.corrected = corrected
        self.timestamp = timestamp
    }
}

// ============================================================
// MARK: - RPE Residual
// ============================================================

/// Per-dot reprojection error used by solvers and overlays.
public struct RPEResidual: Sendable {
    public let id: Int
    public let error: SIMD2<Float>
    public let weight: Float

    public init(id: Int,
                error: SIMD2<Float>,
                weight: Float = 1.0) {
        self.id = id
        self.error = error
        self.weight = weight
    }
}

// ============================================================
// MARK: - RS-PnP Result
// ============================================================

/// Full rolling-shutter SE(3) pose + motion state.
public struct RSPnPResult: Sendable {

    public let R: simd_float3x3        // rotation matrix
    public let t: SIMD3<Float>         // translation (camera-space)
    public let w: SIMD3<Float>         // angular velocity (rad/s)
    public let v: SIMD3<Float>         // translational velocity (m/s)

    public let residual: Float         // LM solver residual
    public let isValid: Bool

    public init(R: simd_float3x3,
                t: SIMD3<Float>,
                w: SIMD3<Float>,
                v: SIMD3<Float>,
                residual: Float,
                isValid: Bool) {
        self.R = R
        self.t = t
        self.w = w
        self.v = v
        self.residual = residual
        self.isValid = isValid
    }
}

// ============================================================
// MARK: - Ballistics Result
// ============================================================

/// Full flight prediction generated by BallisticsSolver.
/// All values are expressed in meters, seconds, and degrees.
/// Independent of spin and pose types (SpinResult, RSPnPResult).
public struct BallisticsResult: Sendable {

    /// Maximum vertical height reached by the ball (meters).
    public let apexHeight: Float

    /// Carry distance until first ground impact (meters).
    public let carryDistance: Float

    /// Total distance, including roll approximation (meters).
    public let totalDistance: Float

    /// Lateral curvature (meters), positive = right, negative = left.
    public let curvature: Float

    /// Total flight time until first landing (seconds).
    public let timeOfFlight: Float

    /// Launch angle relative to horizontal (degrees).
    public let launchAngle: Float

    /// Landing angle relative to horizontal at impact (degrees).
    public let landingAngle: Float

    /// Prediction validity flag (true if all physics remained stable).
    public let isValid: Bool

    public init(
        apexHeight: Float,
        carryDistance: Float,
        totalDistance: Float,
        curvature: Float,
        timeOfFlight: Float,
        launchAngle: Float,
        landingAngle: Float,
        isValid: Bool
    ) {
        self.apexHeight = apexHeight
        self.carryDistance = carryDistance
        self.totalDistance = totalDistance
        self.curvature = curvature
        self.timeOfFlight = timeOfFlight
        self.launchAngle = launchAngle
        self.landingAngle = landingAngle
        self.isValid = isValid
    }
}

// ============================================================
// MARK: - SpinResult
// ============================================================

/// Spin estimation from dot-phase + RS timing.
public struct SpinResult: Sendable {
    public let omega: SIMD3<Float>     // rad/s
    public let rpm: Float
    public let axis: SIMD3<Float>      // unit axis in camera coords
    public let confidence: Float       // 0–1

    public init(omega: SIMD3<Float>,
                rpm: Float,
                axis: SIMD3<Float>,
                confidence: Float) {
        self.omega = omega
        self.rpm = rpm
        self.axis = axis
        self.confidence = confidence
    }
}

// ============================================================
// MARK: - Spin Drift
// ============================================================

/// Frame-to-frame spin axis drift for stabilization + overlays.
public struct SpinDriftMetrics: Sendable {
    public let deltaAxis: SIMD3<Float>   // difference between frames
    public let driftRate: Float          // deg/frame
    public let stability: Float          // 0–1

    public init(deltaAxis: SIMD3<Float>,
                driftRate: Float,
                stability: Float) {
        self.deltaAxis = deltaAxis
        self.driftRate = driftRate
        self.stability = stability
    }
}
// ============================================================
// MARK: - Calibration Result
// ============================================================

/// Heavy-calibration output used internally by VisionPipeline.
/// This struct contains all estimated alignment and world-frame
/// transforms needed for pose correction, tilt correction, and
/// world-origin alignment.
///
/// NOTE:
/// - Not stored in VisionFrameData.
/// - Not persisted across launches unless you decide later.
/// - Used only by AutoCalibration + TiltCorrection.
public struct CalibrationResult: Sendable {

    /// Camera roll angle (radians)
    public let roll: Float

    /// Camera pitch angle (radians)
    public let pitch: Float

    /// Yaw offset between camera frame and target line (radians)
    public let yawOffset: Float

    /// Estimated distance from camera to tee (meters)
    public let cameraToTeeDistance: Float

    /// Estimated launch origin in camera coordinates
    public let launchOrigin: SIMD3<Float>

    /// World-frame alignment rotation matrix
    public let worldAlignmentR: simd_float3x3

    public init(
        roll: Float,
        pitch: Float,
        yawOffset: Float,
        cameraToTeeDistance: Float,
        launchOrigin: SIMD3<Float>,
        worldAlignmentR: simd_float3x3
    ) {
        self.roll = roll
        self.pitch = pitch
        self.yawOffset = yawOffset
        self.cameraToTeeDistance = cameraToTeeDistance
        self.launchOrigin = launchOrigin
        self.worldAlignmentR = worldAlignmentR
    }
}
// ============================================================
// MARK: - Vision Frame Data
// ============================================================

/// The unified output of VisionPipeline.
/// Every subsystem must depend on this structure only.
public struct VisionFrameData: Sendable {

    public let timestamp: Double
    public let pixelBuffer: CVPixelBuffer
    public let width: Int
    public let height: Int
    public let intrinsics: CameraIntrinsics

    public let dots: [VisionDot]
    public let trackingState: DotTrackingState

    // Rolling shutter
    public let bearings: [RSBearing]?
    public let correctedPoints: [RSCorrectedPoint]?

    // Pose + motion
    public let rspnp: RSPnPResult?

    // Spin
    public let spin: SpinResult?
    public let spinDrift: SpinDriftMetrics?

    // Residuals
    public let residuals: [RPEResidual]?

    // Debug
    public let flowVectors: [SIMD2<Float>]?

    public init(
        timestamp: Double,
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        intrinsics: CameraIntrinsics,
        dots: [VisionDot],
        trackingState: DotTrackingState,
        bearings: [RSBearing]? = nil,
        correctedPoints: [RSCorrectedPoint]? = nil,
        rspnp: RSPnPResult? = nil,
        spin: SpinResult? = nil,
        spinDrift: SpinDriftMetrics? = nil,
        residuals: [RPEResidual]? = nil,
        flowVectors: [SIMD2<Float>]? = nil
    ) {
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.width = width
        self.height = height
        self.intrinsics = intrinsics
        self.dots = dots
        self.trackingState = trackingState
        self.bearings = bearings
        self.correctedPoints = correctedPoints
        self.rspnp = rspnp
        self.spin = spin
        self.spinDrift = spinDrift
        self.residuals = residuals
        self.flowVectors = flowVectors
    }
}
