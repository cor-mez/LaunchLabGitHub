//
//  VisionTypes.swift
//  LaunchLab
//
//  Frozen Architecture -- v1.2 (+ VisionDot.score, + ballRadiusPx)
//
//  Defines ALL cross-module data contracts.

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
// MARK: - Vision Dot  (UPDATED — now supports FAST9 score)
// ============================================================

public struct VisionDot: Identifiable, Sendable {
    public let id: Int
    public let position: CGPoint
    public let score: Float           // ← NEW
    public let predicted: CGPoint?
    public let velocity: CGVector?

    public init(
        id: Int,
        position: CGPoint,
        score: Float,
        predicted: CGPoint? = nil,
        velocity: CGVector? = nil
    ) {
        self.id = id
        self.position = position
        self.score = score
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

    public let R: simd_float3x3
    public let t: SIMD3<Float>
    public let w: SIMD3<Float>
    public let v: SIMD3<Float>
    public let residual: Float
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
    public let omega: SIMD3<Float>
    public let rpm: Float
    public let axis: SIMD3<Float>
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

// MARK: - VisionFrameData

public struct VisionFrameData {

    // ======================================================
    // NEW: RAW FAST9 POINTS
    // ======================================================
    /// Raw FAST9 corner detections in full-frame pixel coords.
    /// Populated BEFORE BallLock filtering.
    public let rawDetectionPoints: [CGPoint]?

    // ======================================================
    // EXISTING: FILTERED DOTS (ball-only once locked)
    // ======================================================
    public let dots: [VisionDot]

    public let timestamp: Double
    public let pixelBuffer: CVPixelBuffer
    public let width: Int
    public let height: Int
    public let intrinsics: CameraIntrinsics

    public let trackingState: DotTrackingState
    public let bearings: [Float]?
    public let correctedPoints: [CGPoint]?
    public let rspnp: RSPnPResult?
    public let spin: SpinResult?
    public let spinDrift: SpinDriftMetrics?
    public let residuals: [RPEResidual]?
    public let flowVectors: [SIMD2<Float>]?

    // ======================================================
    // INIT UPDATED FOR RAW FAST9 SUPPORT
    // ======================================================
    public init(
        rawDetectionPoints: [CGPoint]? = nil,
        dots: [VisionDot],
        timestamp: Double,
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        intrinsics: CameraIntrinsics,
        trackingState: DotTrackingState,
        bearings: [Float]?,
        correctedPoints: [CGPoint]?,
        rspnp: RSPnPResult?,
        spin: SpinResult?,
        spinDrift: SpinDriftMetrics?,
        residuals: [RPEResidual]?,
        flowVectors: [SIMD2<Float>]?
    ) {
        self.rawDetectionPoints = rawDetectionPoints
        self.dots = dots
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
        self.width = width
        self.height = height
        self.intrinsics = intrinsics
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
