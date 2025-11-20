//
//  VisionTypes.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd
import CoreGraphics

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
            SIMD3<Float>(fx,  0,  cx),
            SIMD3<Float>( 0, fy,  cy),
            SIMD3<Float>( 0,  0,   1)
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

    public init(id: Int, position: CGPoint, predicted: CGPoint, velocity: CGVector? = nil) {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.velocity = velocity
    }

    @inline(__always)
    public func updating(predicted: CGPoint, velocity: CGVector?) -> VisionDot {
        VisionDot(id: id, position: position, predicted: predicted, velocity: velocity)
    }
}

// ============================================================
// MARK: - RS Bearing
// ============================================================

public struct RSBearing {
    public let id: Int                  // dot index
    public let modelPoint: SIMD3<Float> // 3D dot on ball
    public let bearing: SIMD3<Float>    // normalized ray
    public let timestamp: Float         // RS timestamp
}

// ============================================================
// MARK: - RS Corrected Point
// ============================================================

public struct RSCorrectedPoint {
    public let id: Int
    public let modelPoint: SIMD3<Float>
    public let correctedBearing: SIMD3<Float>
    public let timestamp: Float
}

// ============================================================
// MARK: - Rolling-Shutter PnP Result (v2)
// ============================================================

public struct RSPnPResult {
    public let R: simd_float3x3
    public let T: SIMD3<Float>
    public let w: SIMD3<Float>      // angular velocity (rad/s)
    public let v: SIMD3<Float>      // linear velocity (m/s)
    public let residual: Float      // RMS reprojection
    public let isValid: Bool
}

// ============================================================
// MARK: - SpinResult
// ============================================================

public struct SpinResult {
    public let axis: SIMD3<Float>      // unit vector spin axis
    public let omega: SIMD3<Float>     // angular velocity (rad/s)
    public let rpm: Float              // user-visible metric

    public static let zero = SpinResult(
        axis: SIMD3<Float>(0,0,1),
        omega: SIMD3<Float>(0,0,0),
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

public final class VisionFrameData {

    // Core frame data
    public let pixelBuffer: CVPixelBuffer
    public let width: Int
    public let height: Int
    public let timestamp: CFTimeInterval
    public let intrinsics: CameraIntrinsics

    // Pipeline outputs
    public var pose: PoseSolver.Pose?
    public var dots: [VisionDot]

    public var rsLineIndex: [Int] = []
    public var rsTimestamps: [Float] = []
    public var rsBearings: [RSBearing] = []
    public var rsCorrected: [RSCorrectedPoint] = []
    public var rspnp: RSPnPResult?

    public var spin: SpinResult?
    public var rsResiduals: [RPEResidual] = []

    public var lkDebug: PyrLKDebugInfo = PyrLKDebugInfo()

    // ========================================================
    // NEW -- Spin Drift Metrics
    // ========================================================
    public var spinDrift: SpinDriftMetrics = .zero

    // --------------------------------------------------------
    // Init
    // --------------------------------------------------------
    public init(
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