//
//  VisionTypes.swift
//  LaunchLab
//
//  Frozen Architecture -- v1.1 (+ ballRadiusPx field)
//
//  Defines ALL cross-module data contracts.
//  Now includes `ballRadiusPx` so RS-PnP V1.5 can estimate depth.
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

// ============================================================
// MARK: - Camera Intrinsics
// ============================================================

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
            SIMD3(fx, 0,  cx),
            SIMD3(0,  fy, cy),
            SIMD3(0,   0,  1)
        ])

        self.Kinv = self.K.inverse
    }

    public static let zero = CameraIntrinsics(fx: 1, fy: 1, cx: 0, cy: 0)
}

// ============================================================
// MARK: - Vision Dot
// ============================================================

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
    case initial
    case tracking
    case lost
}

// ============================================================
// MARK: - Rolling-Shutter Bearing
// ============================================================

public struct RSBearing: Sendable {
    public let ray: SIMD3<Float>
    public let rowIndex: Int
}

// ============================================================
// MARK: - RS Corrected Pixel
// ============================================================

public struct RSCorrectedPoint: Sendable {
    public let original: CGPoint
    public let corrected: CGPoint
    public let timestamp: Float
}

// ============================================================
// MARK: - RPE Residual
// ============================================================

public struct RPEResidual: Sendable {
    public let id: Int
    public let error: SIMD2<Float>
    public let weight: Float
}

// ============================================================
// MARK: - RSPnPResult (Frozen SE3 Contract)
// ============================================================

public struct RSPnPResult: Sendable {

    public let R: simd_float3x3        // rotation matrix (camera←ball)
    public let t: SIMD3<Float>         // translation (camera coords)
    public let w: SIMD3<Float>         // angular velocity (rad/s)
    public let v: SIMD3<Float>         // translational velocity (m/s)
    public let residual: Float         // LM residual
    public let isValid: Bool

    public init(
        R: simd_float3x3,
        t: SIMD3<Float>,
        w: SIMD3<Float>,
        v: SIMD3<Float>,
        residual: Float,
        isValid: Bool
    ) {
        self.R = R
        self.t = t
        self.w = w
        self.v = v
        self.residual = residual
        self.isValid = isValid
    }
}

// ============================================================
// MARK: - BallisticsResult
// ============================================================

public struct BallisticsResult: Sendable {

    public let apexHeight: Float
    public let carryDistance: Float
    public let totalDistance: Float
    public let curvature: Float
    public let timeOfFlight: Float
    public let launchAngle: Float
    public let landingAngle: Float
    public let isValid: Bool
}

// ============================================================
// MARK: - SpinResult (Frozen Contract)
// ============================================================

public struct SpinResult: Sendable {
    public let omega: SIMD3<Float>   // rad/s
    public let rpm: Float
    public let axis: SIMD3<Float>    // unit vector
    public let confidence: Float
}

// ============================================================
// MARK: - Spin Drift
// ============================================================

public struct SpinDriftMetrics: Sendable {
    public let deltaAxis: SIMD3<Float>
    public let driftRate: Float
    public let stability: Float
}

// ============================================================
// MARK: - Calibration Result
// ============================================================

public struct CalibrationResult: Sendable {

    public let roll: Float
    public let pitch: Float
    public let yawOffset: Float
    public let cameraToTeeDistance: Float
    public let launchOrigin: SIMD3<Float>
    public let worldAlignmentR: simd_float3x3
}

// ============================================================
// MARK: - Vision Frame Data  (UPDATED)
// ============================================================

public struct VisionFrameData: Sendable {

    public let timestamp: Double
    public let pixelBuffer: CVPixelBuffer
    public let width: Int
    public let height: Int
    public let intrinsics: CameraIntrinsics

    public let dots: [VisionDot]
    public let trackingState: DotTrackingState

    // Rolling shutter (optional)
    public let bearings: [RSBearing]?
    public let correctedPoints: [RSCorrectedPoint]?

    // Pose
    public let rspnp: RSPnPResult?

    // Spin
    public let spin: SpinResult?
    public let spinDrift: SpinDriftMetrics?

    // NEW -- required for RS-PnP V1.5 depth estimation
    public let ballRadiusPx: CGFloat?

    // Residuals
    public let residuals: [RPEResidual]?

    // LK flows (for overlays + spin)
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
        ballRadiusPx: CGFloat? = nil,          // NEW
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
        self.ballRadiusPx = ballRadiusPx
        self.residuals = residuals
        self.flowVectors = flowVectors
    }
}