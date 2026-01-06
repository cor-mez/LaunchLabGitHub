//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

final class VisionPipeline {
    private var dotDetector = DotDetector()
    private let dotTracker = DotTracker()
    private let lkRefiner = PyrLKRefiner()
    private let velocityTracker = VelocityTracker()

    private let ballLock = BallLockV5()

    private var rsWindowBuilder = RSWindow()
    private let rspnpSolver = RSPnPBridgeV1()

    private var prevDots: [VisionDot] = []
    private var prevTrackingState: DotTrackingState = .initial
    private var prevPixelBuffer: CVPixelBuffer?
    private var prevTimestamp: Double?
    private var prevLockedDots: [VisionDot] = []
    private var lockedRunLength = 0
    private var frameIndex = 0
    private var lastFrameWidth = 0
    private var lastFrameHeight = 0
    private var lastIntrinsics: (Float,Float,Float,Float)?


    func reset() {
        dotTracker.reset()
        prevDots = []
        prevLockedDots = []
        prevPixelBuffer = nil
        prevTimestamp = nil
        lockedRunLength = 0
        frameIndex = 0
    }

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let intrS = (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
        if lastFrameWidth != 0 {
            if width != lastFrameWidth || height != lastFrameHeight ||
                lastIntrinsics.map({ $0 != intrS }) ?? false {
                reset()
            }
        }
        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsics = intrS

        frameIndex &+= 1
        prevPixelBuffer = pixelBuffer
        prevTimestamp = timestamp

        let minDim = CGFloat(min(width, height))
        let roiSide = minDim * 0.40
        let roiRect = CGRect(
            x: CGFloat(width) * 0.5 - roiSide * 0.5,
            y: CGFloat(height) * 0.5 - roiSide * 0.5,
            width: roiSide,
            height: roiSide
        )

        let rawPoints: [CGPoint] = dotDetector.detect(in: pixelBuffer, roi: roiRect)
        
        let visionDots: [VisionDot] = []

        let frame = VisionFrameData(
            rawDetectionPoints: rawPoints,
            dots: visionDots,
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            trackingState: .initial,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            residuals: nil,
            flowVectors: []
        )

        return frame


        // TRACKING
        let (tracked, trackingState) = dotTracker.track(
            detections: rawPoints,
            previousDots: prevDots,
            previousState: prevTrackingState
        )

        // LK Refinement
        let refined: [VisionDot]
        let flows: [SIMD2<Float>]
        if let prev = prevPixelBuffer {
            let pair = lkRefiner.refine(dots: tracked, prevBuffer: prev, currBuffer: pixelBuffer)
            refined = pair.0
            flows = pair.1
        } else {
            refined = tracked
            flows = []
        }

        // PRE-LOCK FRAME
        let preFrame = VisionFrameData(
            rawDetectionPoints: rawPoints,
            dots: refined,
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            trackingState: trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            residuals: nil,
            flowVectors: flows
        )

        // === Ball cluster, BallLock, RS-PnP code unchanged ===
        // (keep as-is from your existing file)

        // For brevity, we return preFrame until full reintegration:
        prevDots = refined
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevTimestamp = timestamp
        prevLockedDots = refined

        return preFrame
    }
}
