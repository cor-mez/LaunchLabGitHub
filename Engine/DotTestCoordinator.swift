//
//  DotTestCoordinator.swift
//

import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import Metal


@MainActor
final class DotTestCoordinator {

    // MARK: - Singleton
    static let shared = DotTestCoordinator()

    // MARK: - Core Systems
    let mode = DotTestMode.shared
    let detector = MetalDetector.shared
    let renderer = MetalRenderer.shared
    let ballLock = BallLockV0()

    weak var previewView: FounderPreviewView?
    weak var founderDelegate: FounderTelemetryObserver?
    weak var poseEligibilityDelegate: PoseEligibilityDelegate?

    // MARK: - Frame State
    private var frameIndex: Int = 0
    private let detectionInterval: Int = 3

    var lastROI: CGRect  = .zero
    var lastFull: CGSize = .zero
    
    
    // MARK: - BallLock State
    private struct BallLockMemory {
        var center: CGPoint
        var radius: CGFloat
        var age: Int
    }

    private var ballLockMemory: BallLockMemory?
    private var smoothedBallLockCount: Float = 0

    private init() {}

    // =====================================================================
    // MARK: - FRAME ENTRY POINT
    // =====================================================================
    func processFrame(_ pb: CVPixelBuffer, timestamp: CMTime) {

        frameIndex += 1

        guard frameIndex % detectionInterval == 0 else { return }
        guard mode.isArmedForDetection else { return }

        let ts = CMTimeGetSeconds(timestamp)

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }

        let fullSize = CGSize(width: w, height: h)
        lastFull = fullSize

        let roiSize: CGFloat = 100
        let roi = CGRect(
            x: fullSize.width * 0.5 - roiSize * 0.5,
            y: fullSize.height * 0.5 - roiSize * 0.5,
            width: roiSize,
            height: roiSize
        ).integral

        lastROI = roi
        
        if DebugProbe.isEnabled(.capture) {
            Log.info(.detection, "ROI=\(lastROI) full=\(lastFull)")
        }

        detectGPU(
            pb: pb,
            roi: roi,
            fullSize: fullSize,
            timestampSec: ts
        )
    }

    // =====================================================================
    // MARK: - GPU DETECTION (FAST9 READBACK)
    // =====================================================================
    private func detectGPU(
        pb: CVPixelBuffer,
        roi: CGRect,
        fullSize: CGSize,
        timestampSec: Double
    ) {

        detector.fast9ThresholdY = mode.fast9ThresholdY
        detector.fast9ScoreMinY  = mode.fast9ScoreMinY
        detector.nmsRadius       = mode.fast9NmsRadius

        detector.prepareFrameY(
            pb,
            roi: roi,
            srScale: mode.srScale
        )

        let scored = detector.gpuFast9ScoredCornersY()
        guard !scored.isEmpty else {
            publishTelemetry(
                roi: roi,
                fullSize: fullSize,
                locked: false,
                confidence: 0,
                center: nil,
                timestampSec: timestampSec
            )
            return
        }

        let points = scored.map { $0.point }

        if let cluster = ballLock.findBallCluster(from: points) {
            ballLockMemory = BallLockMemory(
                center: cluster.center,
                radius: cluster.radius,
                age: 0
            )
            smoothedBallLockCount =
                0.3 * Float(cluster.count) +
                0.7 * smoothedBallLockCount

            publishTelemetry(
                roi: roi,
                fullSize: fullSize,
                locked: true,
                confidence: smoothedBallLockCount,
                center: cluster.center,
                timestampSec: timestampSec
            )
        } else {
            ballLockMemory = nil
            smoothedBallLockCount = 0

            publishTelemetry(
                roi: roi,
                fullSize: fullSize,
                locked: false,
                confidence: 0,
                center: nil,
                timestampSec: timestampSec
            )
        }
    }

    // =====================================================================
    // MARK: - TELEMETRY
    // =====================================================================
    private func publishTelemetry(
        roi: CGRect,
        fullSize: CGSize,
        locked: Bool,
        confidence: Float,
        center: CGPoint?,
        timestampSec: Double
    ) {

        let telemetry = FounderFrameTelemetry(
            roi: roi,
            fullSize: fullSize,
            ballLocked: locked,
            confidence: confidence,
            center: center,
            mdgDecision: nil,
            motionGatePxPerSec: 0,
            timestampSec: timestampSec,
            sceneScale: SceneScale(
                pixelsPerMeter: Double(max(fullSize.width, fullSize.height))
            )
        )

        previewView?.updateOverlay(
            roi: roi,
            fullSize: fullSize,
            ballLocked: locked,
            confidence: confidence
        )

        founderDelegate?.didUpdateFounderTelemetry(telemetry)
    }
}
