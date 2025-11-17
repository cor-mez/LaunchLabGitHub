// VisionPipeline.swift
// Example integration of VelocityTracker (final stage: DotDetector → DotTracker → PoseSolver → VelocityTracker)

import Foundation
import CoreVideo
import CoreGraphics

public final class VisionPipeline {

    // Existing components
    private let dotDetector = DotDetector()
    private let dotTracker = DotTracker()
    private let poseSolver = PoseSolver()

    // New component
    private let velocityTracker = VelocityTracker()

    public init() {}

    /// Main entry point used by CameraManager.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Current frame buffer.
    ///   - timestamp: Frame timestamp in seconds.
    ///   - intrinsics: Camera intrinsics (dynamic or fallback).
    ///
    /// - Returns: VisionFrameData for overlays.
    public func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // 1) Detect dots (stateless)
        let detectedDots = dotDetector.detectDots(
            in: pixelBuffer,
            width: width,
            height: height
        )

        // 2) Track / stabilize IDs (existing DotTracker behavior)
        let trackedDots = dotTracker.trackDots(
            detectedDots,
            width: width,
            height: height,
            timestamp: timestamp
        )

        // 3) Solve pose from tracked dots
        let imagePoints = trackedDots.map { CGPoint(x: $0.position.x, y: $0.position.y) }
        let modelPoints = DotPattern.shared.modelPoints   // adjust if your pattern lives elsewhere

        let pose = poseSolver.solvePose(
            modelPoints: modelPoints,
            imagePoints: imagePoints,
            intrinsics: intrinsics
        )

        // 4) VelocityTracker: compute per-dot flow + predicted next position
        let velocityDots = velocityTracker.process(
            dots: trackedDots,
            pixelBuffer: pixelBuffer,
            timestamp: timestamp
        )

        // 5) Build frame data (Model 1: latestFrame used by overlays)
        let frameData = VisionFrameData(
            dots: velocityDots,
            pose: pose,
            width: width,
            height: height,
            timestamp: timestamp,
            intrinsics: intrinsics
        )

        return frameData
    }

    /// Reset internal state when capture restarts or configuration changes.
    public func reset() {
        velocityTracker.reset()
        dotTracker.reset()
        // dotDetector and poseSolver remain stateless by design
    }
}
