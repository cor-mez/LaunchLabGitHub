// File: Engine/VisionPipelineActor.swift
//
//  VisionPipelineActor.swift
//  LaunchLab
//
//  Lightweight actor wrapper around VisionPipeline to keep
//  heavy vision work off the main thread.
//

import Foundation
import CoreVideo

actor VisionPipelineActor {

    let pipeline: VisionPipeline
    private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    init(config: BallLockConfig) {
        self.pipeline = VisionPipeline(ballLockConfig: config)
    }

    /// Update the latest thermal state (can be used for gating by caller).
    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
    }

    /// Asynchronous frame processing entry point.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Camera frame buffer.
    ///   - timestamp:   Host time (seconds).
    ///   - intrinsics:  Camera intrinsics for this frame.
    ///   - imu:         IMU state (not yet consumed by VisionPipeline V1).
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics,
        imu: IMUState
    ) async -> VisionFrameData? {
        // IMU + thermalState can be used here for future gating if needed.
        _ = imu
        _ = thermalState

        return pipeline.processFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            intrinsics: intrinsics
        )
    }
}
