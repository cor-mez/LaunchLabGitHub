//
//  CameraIntrinsics.swift
//  LaunchLab
//

import Foundation
import simd

/// Immutable camera intrinsics for 720×1280 portrait mode.
public struct CameraIntrinsics: Sendable {
    public let fx: Float
    public let fy: Float
    public let cx: Float
    public let cy: Float
    public let width: Int
    public let height: Int

    public var matrix: simd_float3x3 {
        simd_float3x3([
            SIMD3(fx,   0,  cx),
            SIMD3(0,   fy, cy),
            SIMD3(0,    0,  1)
        ])
    }
}

public extension CameraIntrinsics {

    /// Standard iPhone 240 FPS portrait intrinsics for 720×1280.
    static let iPhone240_720x1280 = CameraIntrinsics(
        fx: 720 * 0.95,           // ~684 pixels
        fy: 720 * 0.95,           // same focal length
        cx: 720 * 0.5,            // principal point center X
        cy: 1280 * 0.5,           // principal point center Y
        width: 720,
        height: 1280
    )
}
