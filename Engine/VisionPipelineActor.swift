//
//  VisionPipelineActor.swift
//  LaunchLab
//
//  Actor-isolated observability wrapper for VisionPipeline.
//
//  ROLE (STRICT):
//  - Perform heavy vision / RS observability off the main thread
//  - Guarantee per-frame isolation of VisionPipeline execution
//  - NEVER reference authority, lifecycle, or shot decisions
//

import Foundation
import CoreVideo

actor VisionPipelineActor {

    // -------------------------------------------------------------------------
    // MARK: - Stored Properties (ACTOR-ISOLATED)
    // -------------------------------------------------------------------------

    /// Observability-only pipeline.
    /// Must never be accessed outside this actor.
    private let pipeline: VisionPipeline

    /// Cached thermal state for future observational gating.
    /// Not used for authority.
    private var thermalState: ProcessInfo.ThermalState =
        ProcessInfo.processInfo.thermalState

    // -------------------------------------------------------------------------
    // MARK: - Initializer
    // -------------------------------------------------------------------------

    init(pipeline: VisionPipeline) {
        self.pipeline = pipeline
    }

    // -------------------------------------------------------------------------
    // MARK: - Thermal State (OBSERVATIONAL)
    // -------------------------------------------------------------------------

    /// Updates thermal state for observability diagnostics.
    /// Does NOT affect authority or acceptance.
    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
    }

    // -------------------------------------------------------------------------
    // MARK: - Frame Processing (OBSERVATIONAL ONLY)
    // -------------------------------------------------------------------------

    /// Asynchronous observability entry point.
    ///
    /// IMPORTANT:
    /// - This function MUST remain authority-free.
    /// - Returned VisionFrameData is frame-scoped and non-authoritative.
    /// - All shot decisions must occur elsewhere via ShotLifecycleController.
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics,
        imu: IMUState
    ) async -> VisionFrameData {

        // Explicitly unused in V1; retained for future observability
        _ = imu
        _ = thermalState

        return pipeline.processFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            intrinsics: intrinsics
        )
    }
}
