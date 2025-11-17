//
//  VisionTypes.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import simd

// ---------------------------------------------------------
// MARK: - VisionDot
// ---------------------------------------------------------

public struct VisionDot: Sendable {
    public let id: Int
    public let position: CGPoint
    public let predicted: CGPoint?
    public let confidence: Float
    public let fbError: Float

    public init(id: Int,
                position: CGPoint,
                predicted: CGPoint?,
                confidence: Float,
                fbError: Float)
    {
        self.id = id
        self.position = position
        self.predicted = predicted
        self.confidence = confidence
        self.fbError = fbError
    }
}

// ---------------------------------------------------------
// MARK: - VisionPose
// ---------------------------------------------------------

public struct VisionPose: Sendable {
    public let rotation: simd_float3x3
    public let quaternion: simd_quatf
    public let translation: SIMD3<Float>
    public let yaw: Float
    public let pitch: Float
    public let roll: Float
    public let rmsError: Float

    public init(rotation: simd_float3x3,
                quaternion: simd_quatf,
                translation: SIMD3<Float>,
                yaw: Float,
                pitch: Float,
                roll: Float,
                rmsError: Float)
    {
        self.rotation = rotation
        self.quaternion = quaternion
        self.translation = translation
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.rmsError = rmsError
    }
}

// ---------------------------------------------------------
// MARK: - VisionFrameData
// ---------------------------------------------------------

public struct VisionFrameData: Sendable {
    public let dots: [VisionDot]
    public let pose: VisionPose?
    public let width: Int
    public let height: Int
    public let timestamp: Double

    public init(dots: [VisionDot],
                pose: VisionPose?,
                width: Int,
                height: Int,
                timestamp: Double)
    {
        self.dots = dots
        self.pose = pose
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}
