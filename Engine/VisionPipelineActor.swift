// File: Engine/VisionPipelineActor.swift
//
//  VisionPipelineActor.swift
//  LaunchLab
//

import Foundation
import CoreVideo

actor VisionPipelineActor {

    let pipeline: VisionPipeline
    private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    init(config: BallLockConfig) {
        self.pipeline = VisionPipeline(ballLockConfig: config)
        pipeline.thermalState = thermalState
    }

    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
        pipeline.thermalState = state
    }

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics,
        imu: IMUState
    ) async -> VisionFrameData? {
        pipeline.thermalState = thermalState
        return pipeline.processFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            intrinsics: intrinsics,
            imuState: imu
        )
    }
}
