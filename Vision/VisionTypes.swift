import Foundation
import CoreGraphics
import simd

// MARK: - VisionPose

struct VisionPose {
    var rotationMatrix: simd_float3x3
    var translation: SIMD3<Float>
    var quaternion: simd_quatf
    var yaw: Float
    var pitch: Float
    var roll: Float
    var rmsError: Float
}
