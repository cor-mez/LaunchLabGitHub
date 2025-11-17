//
//  CameraIntrinsics.swift
//  LaunchLab
//

import Foundation
import simd

/// Immutable camera intrinsics for any resolution.
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

// -------------------------------------------------------------
// MARK: - Presets / Utility
// -------------------------------------------------------------
public extension CameraIntrinsics {

    /// A safe default used before real metadata has arrived.
    static let zero = CameraIntrinsics(
        fx: 0, fy: 0,
        cx: 0, cy: 0,
        width: 0, height: 0
    )

    /// Simple fallback intrinsics for legacy portrait 720×1280.
    /// (Use only for debugging; real app uses metadata intrinsics.)
    static let iPhone240_720x1280 = CameraIntrinsics(
        fx: 720 * 0.95,
        fy: 720 * 0.95,
        cx: 720 * 0.5,
        cy: 1280 * 0.5,
        width: 720,
        height: 1280
    )
}
