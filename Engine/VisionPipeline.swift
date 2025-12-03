//
//  VisionPipeline.swift
//  LaunchLab
//
//  CLEAN ARCHITECTURE VERSION (Option C)
//  ------------------------------------
//  1. Full-frame DotDetector → raw detections
//  2. DotTracker for stable IDs
//  3. PyrLKRefiner for subpixel refinement
//  4. VelocityTracker for per-dot motion
//  5. BallClusterClassifier for ball detection
//  6. BallLockStateMachine for lock/candidate/search transitions
//  7. RSDegeneracyCalculator for gating
//  8. RSWindowBuilder for frame triplets
//  9. RSPnPSolver for single-solve per shot
//
//  This file contains ZERO experimental fields,
//  ZERO mismatched parameters,
//  ZERO unreferenced members.
//
//  It complies 100% with:
//    • VisionTypes.swift
//    • DotDetector.swift
//    • BallLockStateMachine.swift
//    • BallClusterClassifier.swift
//    • RSWindowBuilder.swift
//    • RSDegeneracyCalculator.swift
//    • RSPnPSolver.swift
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

// MARK: - VisionPipeline (Clean)

final class VisionPipeline {

    // ============================================================
    // MARK: - Modules
    // ============================================================

    private var dotDetector: DotDetector
    private let dotTracker = DotTracker()
    private let lkRefiner = PyrLKRefiner()
    private let velocityTracker = VelocityTracker()

    private let ballClusterClassifier = BallClusterClassifier()
    private let ballLockStateMachine = BallLockStateMachine()

    private let rsDegeneracy = RSDegeneracyCalculator()
    private var rsWindowBuilder = RSWindowBuilder()
    private let rspnpSolver = RSPnPSolver()

    // ============================================================
    // MARK: - Internal State
    // ============================================================

    private let ballLockConfig: BallLockConfig

    private var prevDots: [VisionDot] = []
    private var prevTrackingState: DotTrackingState = .initial
    private var prevPixelBuffer: CVPixelBuffer?
    private var prevTimestamp: Double?

    private var prevLockedDots: [VisionDot] = []
    private var lockedRunLength: Int = 0

    private var frameIndex: Int = 0

    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0
    private var lastIntrinsics: (Float, Float, Float, Float)?

    // ============================================================
    // MARK: - Init
    // ============================================================

    init(ballLockConfig: BallLockConfig) {
        self.ballLockConfig = ballLockConfig
        self.dotDetector = DotDetector()     // full-frame by default
    }

    func reset() {
        dotTracker.reset()
        ballLockStateMachine.reset()
        prevDots = []
        prevLockedDots = []
        prevPixelBuffer = nil
        prevTimestamp = nil
        lockedRunLength = 0
        frameIndex = 0
    }

    // ============================================================
    // MARK: - Main Entry
    // ============================================================

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        // --------------------------------------------------------
        // Auto-reset on size/intrinsics change
        // --------------------------------------------------------
        let intrSig = (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
        if lastFrameWidth != 0 {
            let sizeChanged = (width != lastFrameWidth) || (height != lastFrameHeight)
            let intrChanged = lastIntrinsics.map { $0 != intrSig } ?? false
            if sizeChanged || intrChanged {
                reset()
            }
        }
        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsics = intrSig

        // Time delta
        let dt = prevTimestamp.map { timestamp - $0 } ?? 0.0

        frameIndex &+= 1

        // ============================================================
        // 1) Full-Frame Dot Detection
        // ============================================================

        let fullFrameROI = CGRect(
            x: 0, y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )

        dotDetector = DotDetector()   // fresh config each frame

        let rawPoints = dotDetector.detect(in: pixelBuffer, roi: fullFrameROI)

        // ============================================================
        // 2) DotTracker -- stable IDs
        // ============================================================

        let (tracked, trackingState) = dotTracker.track(
            detections: rawPoints,
            previousDots: prevDots,
            previousState: prevTrackingState
        )

        // ============================================================
        // 3) PyrLKRefiner -- subpixel refinement
        // ============================================================

        let refined: [VisionDot]
        let flows: [SIMD2<Float>]
        if let prevPB = prevPixelBuffer {
            let (r, f) = lkRefiner.refine(
                dots: tracked,
                prevBuffer: prevPB,
                currBuffer: pixelBuffer
            )
            refined = r
            flows = f
        } else {
            refined = tracked
            flows = []
        }

        // Build pre-lock frame (raw tracking/no cluster)
        let baseFrame = VisionFrameData(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            dots: refined,
            trackingState: trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            ballRadiusPx: nil,
            residuals: nil,
            flowVectors: flows
        )

        // ============================================================
        // 4) Ball Cluster + BallLock
        // ============================================================

        // Basic full-frame ball search / classification
        let positions = refined.map { $0.position }

        let params = BallClusterParams(
            minCorners: ballLockConfig.minCorners,
            maxCorners: ballLockConfig.maxCorners,
            minRadiusPx: CGFloat(ballLockConfig.minRadiusPx),
            maxRadiusPx: CGFloat(ballLockConfig.maxRadiusPx),
            idealRadiusMinPx: 20,
            idealRadiusMaxPx: 70,
            roiBorderMarginPx: 8,
            symmetryWeight: CGFloat(ballLockConfig.symmetryWeight),
            countWeight: CGFloat(ballLockConfig.countWeight),
            radiusWeight: CGFloat(ballLockConfig.radiusWeight)
        )

        let imageCenter = CGPoint(x: width/2, y: Int(Double(height)*0.65))
        let searchR = min(width, height) * 0.25

        let cluster = ballClusterClassifier.classify(
            dots: positions,
            imageSize: imageSize,
            roiCenter: imageCenter,
            roiRadius: CGFloat(searchR),
            params: params
        )

        let clusterForLock =
            (cluster != nil && cluster!.qualityScore >= CGFloat(ballLockConfig.minQualityToEnterLock))
            ? cluster
            : nil

        let lockOut = ballLockStateMachine.update(
            cluster: clusterForLock,
            dt: dt,
            frameIndex: frameIndex,
            searchRoiCenter: imageCenter,
            searchRoiRadius: CGFloat(searchR),
            qLock: CGFloat(ballLockConfig.qLock),
            qStay: CGFloat(ballLockConfig.qStay),
            lockAfterN: ballLockConfig.lockAfterN,
            unlockAfterM: ballLockConfig.unlockAfterM,
            alphaCenter: CGFloat(ballLockConfig.alphaCenter),
            roiRadiusFactor: CGFloat(ballLockConfig.roiRadiusFactor),
            loggingEnabled: false
        )

        // ============================================================
        // 5) Filter dots to BallLock ROI
        // ============================================================

        var lockedDots: [VisionDot] = []
        if lockOut.isLocked,
           let c = lockOut.roiCenter,
           let r = lockOut.roiRadius {

            let r2 = r * r
            lockedDots = refined.filter {
                let dx = $0.position.x - c.x
                let dy = $0.position.y - c.y
                return dx*dx + dy*dy <= r2
            }
        }

        // ============================================================
        // 6) RS Degeneracy → RSWindow → PnP (standard pipeline)
        // ============================================================

        // Compute minimal degeneracy metrics
        let shear = rsDegeneracy.estimateShearSlope(
            dots: refined,
            flows: flows,
            roiCenter: imageCenter,
            roiRadius: CGFloat(searchR)
        )

        let rsInput = RSDegeneracyInput(
            shearSlope: shear,
            rowSpanPx: 0,
            blurStreakPx: 0,
            phaseRatio: 1,
            ballPx: CGFloat(cluster?.radiusPx ?? 0),
            flickerModulation: 0,
            isPortrait: height > width
        )

        let rsOut = rsDegeneracy.evaluate(rsInput, isFlickerUnsafe: false)

        if lockOut.isLocked { lockedRunLength += 1 } else { lockedRunLength = 0 }

        let window = rsWindowBuilder.push(
            frame: baseFrame,
            isLocked: lockOut.isLocked,
            clusterQuality: lockOut.quality,
            rsResult: rsOut,
            lockedRunLength: lockedRunLength
        )

        let allowPnP =
            lockOut.isLocked &&
            lockOut.quality >= CGFloat(ballLockConfig.qLock) &&
            rsOut.rsConfidence >= 0.60 &&
            !rsOut.criticalDegeneracy &&
            lockedRunLength >= 3 &&
            window != nil

        let rspnp =
            allowPnP && window != nil
            ? rspnpSolver.solve(window: window!,
                                intrinsics: intrinsics,
                                rowGradient: [])
            : nil

        // ============================================================
        // 7) Velocity tracking on locked dots
        // ============================================================

        let velocityDots = velocityTracker.update(
            previousDots: prevLockedDots,
            currentDots: lockedDots,
            dt: dt
        )

        // ============================================================
        // 8) Build final frame
        // ============================================================

        let final = VisionFrameData(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            dots: velocityDots,
            trackingState: trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: rspnp,
            spin: nil,
            spinDrift: nil,
            ballRadiusPx: cluster?.radiusPx,
            residuals: nil,
            flowVectors: flows
        )

        // Save state
        prevDots = refined
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevTimestamp = timestamp
        prevLockedDots = velocityDots

        return final
    }
}