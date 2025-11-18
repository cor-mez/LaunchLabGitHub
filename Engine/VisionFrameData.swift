//
//  VisionFrameData.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd

final class VisionFrameData {

    let pixelBuffer: CVPixelBuffer
    let width: Int
    let height: Int
    let timestamp: CFTimeInterval
    let intrinsics: CameraIntrinsics

    var pose: PoseSolver.Pose?
    var dots: [VisionDot]

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
