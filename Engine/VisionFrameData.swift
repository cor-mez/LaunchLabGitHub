//
//  VisionFrameData.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd

// ============================================================
// MARK: - Camera Intrinsics
// ============================================================

public struct CameraIntrinsics {
    public let fx: Float
    public let fy: Float
    public let cx: Float
    public let cy: Float
    public let width: Int
    public let height: Int

    public var matrix: simd_float3x3 {
        simd_float3x3(rows: [
            SIMD3(fx,  0,  cx),
            SIMD3( 0, fy,  cy),
            SIMD3( 0,  0,   1)
        ])
    }

    public static let zero = CameraIntrinsics(
        fx: 0, fy: 0,
        cx: 0, cy: 0,
        width: 0, height: 0
    )
}

// ============================================================
// MARK: - VisionDot
// ============================================================

public struct VisionDot {
    public let id: Int
    public var position: CGPoint
    public var predicted: CGPoint
    public var velocity: CGVector?

    public init(id: Int, position: CGPoint, predicted: CGPoint) {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.velocity = nil
    }
}

// ============================================================
// MARK: - RS Bearing
// ============================================================

public struct RSBearing {
    public let index: Int
    public let timestamp: Float
    public let bearing: SIMD3<Float>
}

// ============================================================
// MARK: - RS Corrected Point
// ============================================================

public struct RSCorrectedPoint {
    public let index: Int
    public let timestamp: Float
    public let corrected: SIMD3<Float>
}

// ============================================================
// MARK: - RSPnP Result
// ============================================================

public struct RSPnPResult {
    public let R: simd_float3x3
    public let T: SIMD3<Float>
    public let inliers: Int
}

// ============================================================
// MARK: - SpinResult
// ============================================================

public struct SpinResult {
    public let axis: SIMD3<Float>      // unit vector
    public let omega: SIMD3<Float>     // rad/s
    public let rpm: Float

    public static let zero = SpinResult(
        axis: SIMD3(0,0,1),
        omega: SIMD3(0,0,0),
        rpm: 0
    )
}

// ============================================================
// MARK: - RPE Residual
// ============================================================

public struct RPEResidual {
    public let modelIndex: Int
    public let pixel: SIMD2<Float>
    public let reproj: SIMD2<Float>
    public let error: Float
}

// ============================================================
// MARK: - LK Debug
// ============================================================

public struct PyrLKDebugInfo {
    public var lostCount: Int = 0
    public var rmsError: Float = 0
}

// ============================================================
// MARK: - VisionFrameData
// ============================================================

final class VisionFrameData {

    // --------------------------------------------------------
    // MARK: Core Frame Info
    // --------------------------------------------------------
    let pixelBuffer: CVPixelBuffer
    let width: Int
    let height: Int
    let timestamp: CFTimeInterval
    let intrinsics: CameraIntrinsics

    // --------------------------------------------------------
    // MARK: Vision Pipeline Outputs
    // --------------------------------------------------------
    public var pose: PoseSolver.Pose?
    public var dots: [VisionDot]

    public var rsLineIndex: [Int] = []
    public var rsTimestamps: [Float] = []
    public var rsBearings: [RSBearing] = []
    public var rsCorrected: [RSCorrectedPoint] = []
    public var rspnp: RSPnPResult?

    public var spin: SpinResult?
    public var spinDrift: SpinDriftMetrics = .zero

    public var rsResiduals: [RPEResidual] = []
    public var lkDebug: PyrLKDebugInfo = PyrLKDebugInfo()

    // --------------------------------------------------------
    // MARK: Ball Flight (NEW)
    // --------------------------------------------------------
    public var flight: BallFlightResult?        // <- added for v1


    // --------------------------------------------------------
    // MARK: Init
    // --------------------------------------------------------
    init(
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        timestamp: CFTimeInterval,
        intrinsics: CameraIntrinsics,
        pose: PoseSolver.Pose?,
        dots: [VisionDot]
    ) {
        self.pixelBuffer = pixelBuffer
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.intrinsics = intrinsics
        self.pose = pose
        self.dots = dots
    }
}