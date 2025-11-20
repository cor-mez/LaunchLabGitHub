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