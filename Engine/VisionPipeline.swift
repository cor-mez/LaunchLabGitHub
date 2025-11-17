//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd

/// Stateless per-frame pipeline:
/// 1. Detect dots
/// 2. Solve pose
/// 3. Build VisionFrameData
/// 4. Emit to overlays
@MainActor
public final class VisionPipeline {

    // Singleton (MainActor)
    public static let shared = VisionPipeline()

    // Core modules (pure Swift)
    private let detector = DotDetector()
    private let poseSolver = PoseSolver()

    /// Frame callback for overlays/UI
    public var onFrame: ((VisionFrameData) -> Void)?

    private init() {}

    // ---------------------------------------------------------
    // MARK: - Entry Point (from CameraManager)
    // ---------------------------------------------------------
    public func process(pixelBuffer pb: CVPixelBuffer, timestamp: Double) {

        // Extract buffer dims
        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)

        // Lock Y-plane
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        guard let yPtr = base?.assumingMemoryBound(to: UInt8.self) else { return }

        // ---------------------------------------------------------
        // 1. Dot Detection (stateless)
        // ---------------------------------------------------------
        let dots = detector.detectDots(
            yPtr: yPtr,
            width: width,
            height: height,
            stride: stride,
            timestamp: timestamp
        )

        // ---------------------------------------------------------
        // 2. Pose Solve (stateless)
        // ---------------------------------------------------------
        // Use LIVE METADATA intrinsics (from CameraManager)
        let intr = CameraManager.shared.intrinsics

        let pts2D = dots.map { $0.position }

        let pose = poseSolver.solvePose(
            modelPoints: MarkerPattern.model3D,
            imagePoints: pts2D,
            intrinsics: intr
        )

        // ---------------------------------------------------------
        // 3. Build VisionFrameData
        // ---------------------------------------------------------
        let frame = VisionFrameData(
            dots: dots,
            pose: pose,
            width: width,
            height: height,
            timestamp: timestamp
        )

        // ---------------------------------------------------------
        // 4. Emit to overlays/UI
        // ---------------------------------------------------------
        onFrame?(frame)
    }
}
