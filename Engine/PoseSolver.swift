//
//  PoseSolver.swift
//  LaunchLab
//

import Foundation
import simd
import CoreGraphics

/// Swift wrapper for the native EPnP C solver.
/// Works with modelPoints (3D), imagePoints (2D), and camera intrinsics.
final class PoseSolver {

    init() {}

    /// Attempt to solve for camera pose.
    ///
    /// - Parameters:
    ///   - modelPoints: Array of 3D marker coordinates ([SIMD3<Float>])
    ///   - imagePoints: Array of 2D pixel locations ([CGPoint])
    ///   - intrinsics: Camera intrinsics (fx, fy, cx, cy)
    ///
    /// - Returns: VisionPose if successful, else nil
    func solvePose(
        modelPoints: [SIMD3<Float>],
        imagePoints: [CGPoint],
        intrinsics: CameraIntrinsics
    ) -> VisionPose? {

        let count = modelPoints.count
        guard count >= 4 else { return nil }
        guard imagePoints.count == count else { return nil }

        // -------------------------------------------------------------
        // Flatten input into float* arrays for the C EPnP function
        // -------------------------------------------------------------
        var modelFlat = [Float](repeating: 0, count: count * 3)
        var imageFlat = [Float](repeating: 0, count: count * 2)

        for i in 0..<count {
            let m = modelPoints[i]
            modelFlat[i * 3 + 0] = m.x
            modelFlat[i * 3 + 1] = m.y
            modelFlat[i * 3 + 2] = m.z

            let p = imagePoints[i]
            imageFlat[i * 2 + 0] = Float(p.x)
            imageFlat[i * 2 + 1] = Float(p.y)
        }

        // -------------------------------------------------------------
        // Buffers to receive output
        // -------------------------------------------------------------
        var Rflat = [Float](repeating: 0, count: 9)
        var Tflat = [Float](repeating: 0, count: 3)
        var error: Float = 0

        // -------------------------------------------------------------
        // Call native C EPnP solver
        // -------------------------------------------------------------
        let success: Bool = modelFlat.withUnsafeBufferPointer { mPtr in
            imageFlat.withUnsafeBufferPointer { iPtr in
                Rflat.withUnsafeMutableBufferPointer { rPtr in
                    Tflat.withUnsafeMutableBufferPointer { tPtr in
                        withUnsafeMutablePointer(to: &error) { errPtr in
                            solveEPnP(
                                mPtr.baseAddress,
                                iPtr.baseAddress,
                                Int32(count),
                                intrinsics.fx, intrinsics.fy,
                                intrinsics.cx, intrinsics.cy,
                                rPtr.baseAddress,
                                tPtr.baseAddress,
                                errPtr
                            )
                        }
                    }
                }
            }
        }

        guard success else { return nil }

        // -------------------------------------------------------------
        // Convert R & T into simd_float3x3 and SIMD3<Float>
        // -------------------------------------------------------------
        let R = simd_float3x3(
            SIMD3(Rflat[0], Rflat[1], Rflat[2]),
            SIMD3(Rflat[3], Rflat[4], Rflat[5]),
            SIMD3(Rflat[6], Rflat[7], Rflat[8])
        )

        let t = SIMD3<Float>(Tflat[0], Tflat[1], Tflat[2])

        // -------------------------------------------------------------
        // Convert rotation → quaternion
        // -------------------------------------------------------------
        let q = simd_quatf(R)

        // -------------------------------------------------------------
        // Compute yaw/pitch/roll (Z-Y-X convention)
        // -------------------------------------------------------------
        let yaw   = atan2f(R[1,0], R[0,0])
        let pitch = -asinf(R[2,0])
        let roll  = atan2f(R[2,1], R[2,2])

        // -------------------------------------------------------------
        // Package into VisionPose
        // -------------------------------------------------------------
        return VisionPose(
            rotation: R,
            quaternion: q,
            translation: t,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            rmsError: error
        )
    }
}
