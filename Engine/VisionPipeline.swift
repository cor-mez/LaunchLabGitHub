//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

final class VisionPipeline {

    // ============================================================
    // MARK: - Modules
    // ============================================================

    private var dotConfig = DotDetectorConfig()
    private let dotTracker = DotTracker()
    private let lkRefiner = PyrLKRefiner()
    private let velocityTracker = VelocityTracker()

    private let ballClusterClassifier = BallClusterClassifier()
    private let ballLockStateMachine = BallLockStateMachine()

    private let flickerAnalyzer = FlickerAnalyzer()
    private let rsCalculator = RSDegeneracyCalculator()
    private var rsWindowBuilder = RSWindowBuilder()
    private let rspnpSolver = RSPnPSolver()

    // ============================================================
    // MARK: - Config / State
    // ============================================================

    private let ballLockConfig: BallLockConfig
    private var lastConfigResetFlag: Bool = false

    private var prevAllDots: [VisionDot] = []
    private var prevTrackingState: DotTrackingState = .initial
    private var prevPixelBuffer: CVPixelBuffer?
    private var prevTimestamp: Double?

    private var prevBallDots: [VisionDot] = []
    private var lockedRunLength: Int = 0

    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0
    private var lastIntrinsicsSignature: (Float, Float, Float, Float)?
    private var frameIndex: Int = 0

    // ============================================================
    // MARK: - Init
    // ============================================================

    init(ballLockConfig: BallLockConfig) {
        self.ballLockConfig = ballLockConfig
        reset()
    }

    func reset() {
        ballLockStateMachine.reset()
        lockedRunLength = 0
        prevAllDots = []
        prevTrackingState = .initial
        prevPixelBuffer = nil
        prevTimestamp = nil
        prevBallDots = []
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
        // Auto-reset on intrinsics/orientation change
        // --------------------------------------------------------
        let intrSignature = (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
        if lastFrameWidth != 0 {
            let sizeChanged = (width != lastFrameWidth) || (height != lastFrameHeight)
            let intrChanged  = !intrinsicsEqual(lhs: intrSignature, rhs: lastIntrinsicsSignature)
            if sizeChanged || intrChanged { reset() }
        }
        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsicsSignature = intrSignature

        // Config reset
        if ballLockConfig.needsReset != lastConfigResetFlag {
            reset()
            lastConfigResetFlag = ballLockConfig.needsReset
        }

        frameIndex &+= 1

        // --------------------------------------------------------
        // Time delta
        // --------------------------------------------------------
        let dt = prevTimestamp.map { timestamp - $0 } ?? 0.0

        // --------------------------------------------------------
        // Flicker analysis (RS gating)
        // --------------------------------------------------------
        let flicker = flickerAnalyzer.evaluate(pixelBuffer: pixelBuffer)

        // --------------------------------------------------------
        // ⭐ 1) FULL-FRAME RAW FAST9 DETECTION
        // --------------------------------------------------------
        let fullFrameROI = CGRect(
            x: 0, y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )

        dotConfig.useBlueChannel    = true
        dotConfig.blueChromaGain    = 4.0
        dotConfig.preFilterGain     = 1.35
        dotConfig.fast9Threshold    = 14
        dotConfig.vImageThreshold   = 30.0
        dotConfig.useSuperResolution = true
        dotConfig.srScaleOverride   = 2.0

        let detector = DotDetector(config: dotConfig)

        // RAW FAST9 POINTS (full frame)
        let rawDetectionPoints = detector.detect(in: pixelBuffer, roi: fullFrameROI)

        // Feed these as tracking detections
        let detectionPoints = rawDetectionPoints

        // --------------------------------------------------------
        // 2) DotTracker — ID association
        // --------------------------------------------------------
        let (trackedDots, trackingState) = dotTracker.track(
            detections: detectionPoints,
            previousDots: prevAllDots,
            previousState: prevTrackingState
        )

        // --------------------------------------------------------
        // 3) PyrLK refinement
        // --------------------------------------------------------
        let refinedDots: [VisionDot]
        let flows: [SIMD2<Float>]

        if let prev = prevPixelBuffer {
            let pair = lkRefiner.refine(
                dots: trackedDots,
                prevBuffer: prev,
                currBuffer: pixelBuffer
            )
            refinedDots = pair.0
            flows = pair.1
        } else {
            refinedDots = trackedDots
            flows = []
        }

        // --------------------------------------------------------
        // 4) Build base (pre-lock) frame
        // --------------------------------------------------------
        let baseFrame = VisionFrameData(
            rawDetectionPoints: rawDetectionPoints,
            dots: refinedDots,
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

        let principalPoint = CGPoint(x: CGFloat(intrinsics.cx),
                                     y: CGFloat(intrinsics.cy))

        // --------------------------------------------------------
        // ⭐ 5) Correct 8-ft geometry BallLock ROI
        // --------------------------------------------------------
        let ballCenter = CGPoint(
            x: CGFloat(width)  * 0.50,
            y: CGFloat(height) * 0.60
        )

        let ballRadiusPx: CGFloat = 150.0   // tuned for SR2
        // NOW run BallLock using this consistent ROI:
        let frameAfterBallLock = runBallLockStage(
            refinedDots: refinedDots,
            flows: flows,
            imageSize: imageSize,
            searchRoiCenter: ballCenter,
            searchRoiRadius: ballRadiusPx,
            flicker: flicker,
            principalPoint: principalPoint,
            baseFrameData: baseFrame,
            dt: dt,
            frameIndex: frameIndex
        )

        // --------------------------------------------------------
        // 6) Velocity Tracker (post-lock)
        // --------------------------------------------------------
        let ballDotsVelocity = velocityTracker.update(
            previousDots: prevBallDots,
            currentDots: frameAfterBallLock.dots,
            dt: dt
        )

        // --------------------------------------------------------
        // 7) Build final frame for UI
        // --------------------------------------------------------
        let finalFrame = VisionFrameData(
            rawDetectionPoints: rawDetectionPoints,
            dots: ballDotsVelocity,
            timestamp: frameAfterBallLock.timestamp,
            pixelBuffer: frameAfterBallLock.pixelBuffer,
            width: frameAfterBallLock.width,
            height: frameAfterBallLock.height,
            intrinsics: frameAfterBallLock.intrinsics,
            trackingState: frameAfterBallLock.trackingState,
            bearings: frameAfterBallLock.bearings,
            correctedPoints: frameAfterBallLock.correctedPoints,
            rspnp: frameAfterBallLock.rspnp,
            spin: frameAfterBallLock.spin,
            spinDrift: frameAfterBallLock.spinDrift,
            residuals: frameAfterBallLock.residuals,
            flowVectors: frameAfterBallLock.flowVectors
        )

        // --------------------------------------------------------
        // Save historical state
        // --------------------------------------------------------
        prevAllDots = refinedDots
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevTimestamp = timestamp
        prevBallDots = ballDotsVelocity

        return finalFrame
    }

    // ===================================================================
    // MARK: - BallLock + RS + PnP Stage
    // ===================================================================

    private func runBallLockStage(
        refinedDots: [VisionDot],
        flows: [SIMD2<Float>],
        imageSize: CGSize,
        searchRoiCenter: CGPoint,
        searchRoiRadius: CGFloat,
        flicker: FlickerMetrics,
        principalPoint: CGPoint,
        baseFrameData: VisionFrameData,
        dt: Double,
        frameIndex: Int
    ) -> VisionFrameData {

        let cfg = ballLockConfig

        // For SR2 the ball appears 70–150 px radius at 8 ft.
        let params = BallClusterParams(
            minCorners: cfg.minCorners,
            maxCorners: cfg.maxCorners,
            minRadiusPx: CGFloat(cfg.minRadiusPx),
            maxRadiusPx: CGFloat(cfg.maxRadiusPx),
            idealRadiusMinPx: 70.0,
            idealRadiusMaxPx: 150.0,
            roiBorderMarginPx: 10.0,
            symmetryWeight: CGFloat(cfg.symmetryWeight),
            countWeight: CGFloat(cfg.countWeight),
            radiusWeight: CGFloat(cfg.radiusWeight)
        )

        let positions = refinedDots.map { CGPoint(x: CGFloat($0.position.x),
                                                  y: CGFloat($0.position.y)) }

        // -----------------------------
        // 1) Cluster classification
        // -----------------------------
        let cluster = ballClusterClassifier.classify(
            dots: positions,
            imageSize: imageSize,
            roiCenter: searchRoiCenter,
            roiRadius: searchRoiRadius,
            params: params
        )

        let clusterForLock =
            (cluster != nil && cluster!.qualityScore >= CGFloat(cfg.minQualityToEnterLock))
            ? cluster
            : nil

        // -----------------------------
        // 2) BallLock state update
        // -----------------------------
        let lockOutput = ballLockStateMachine.update(
            cluster: clusterForLock,
            dt: dt,
            frameIndex: frameIndex,
            searchRoiCenter: searchRoiCenter,
            searchRoiRadius: searchRoiRadius,
            qLock: CGFloat(cfg.qLock),
            qStay: CGFloat(cfg.qStay),
            lockAfterN: cfg.lockAfterN,
            unlockAfterM: cfg.unlockAfterM,
            alphaCenter: CGFloat(cfg.alphaCenter),
            roiRadiusFactor: CGFloat(cfg.roiRadiusFactor),
            loggingEnabled: false
        )

        // -----------------------------
        // 3) RS Degeneracy
        // -----------------------------
        let shearSlope = rsCalculator.estimateShearSlope(
            dots: baseFrameData.dots,
            flows: flows,
            roiCenter: searchRoiCenter,
            roiRadius: searchRoiRadius
        )

        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for d in refinedDots {
            let p = d.position
            let dx = p.x - searchRoiCenter.x
            let dy = p.y - searchRoiCenter.y
            if dx*dx + dy*dy <= searchRoiRadius * searchRoiRadius {
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
        }
        let rowSpan = maxY > minY ? (maxY - minY) : 0.0

        let rsInput = RSDegeneracyInput(
            shearSlope: shearSlope,
            rowSpanPx: rowSpan,
            blurStreakPx: 0.0,
            phaseRatio: 1.0,
            ballPx: CGFloat(cluster?.radiusPx ?? 0),
            flickerModulation: CGFloat(flicker.flickerModulation),
            isPortrait: imageSize.height > imageSize.width
        )

        let rsResult = rsCalculator.evaluate(
            rsInput,
            isFlickerUnsafe: flicker.isFlickerUnsafe
        )

        // Track locked-run frames
        if lockOutput.isLocked { lockedRunLength &+= 1 }
        else { lockedRunLength = 0 }

        let inLockedWindow = lockedRunLength >= 3

        // -----------------------------
        // 4) Filter to Locked ROI
        // -----------------------------
        var filteredDots: [VisionDot] = []
        if lockOutput.isLocked,
           let roiCenter = lockOutput.roiCenter,
           let roiRadius = lockOutput.roiRadius {

            let r2 = roiRadius * roiRadius
            filteredDots = baseFrameData.dots.filter {
                let dx = $0.position.x - roiCenter.x
                let dy = $0.position.y - roiCenter.y
                return dx*dx + dy*dy <= r2
            }
        }

        // -----------------------------
        // 5) RS Window Builder
        // -----------------------------
        let rsWindow = rsWindowBuilder.push(
            frame: baseFrameData,
            isLocked: lockOutput.isLocked,
            clusterQuality: lockOutput.quality,
            rsResult: rsResult,
            lockedRunLength: lockedRunLength
        )

        let allowHeavy =
            lockOutput.isLocked &&
            lockOutput.quality >= CGFloat(cfg.qLock) &&
            rsResult.rsConfidence >= 0.60 &&
            !rsResult.criticalDegeneracy &&
            !flicker.isFlickerUnsafe &&
            inLockedWindow &&
            rsWindow != nil

        // -----------------------------
        // 6) RS-PnP solve
        // -----------------------------
        let solvedPnP =
            allowHeavy && rsWindow != nil
            ? rspnpSolver.solve(
                window: rsWindow!,
                intrinsics: baseFrameData.intrinsics,
                rowGradient: []   // flicker weighting off for now
            )
            : nil
        // -----------------------------
        // 7) Build output frame
        // -----------------------------
        let newFrame = VisionFrameData(
            rawDetectionPoints: baseFrameData.rawDetectionPoints,
            dots: filteredDots,
            timestamp: baseFrameData.timestamp,
            pixelBuffer: baseFrameData.pixelBuffer,
            width: baseFrameData.width,
            height: baseFrameData.height,
            intrinsics: baseFrameData.intrinsics,
            trackingState: baseFrameData.trackingState,
            bearings: baseFrameData.bearings,
            correctedPoints: baseFrameData.correctedPoints,
            rspnp: solvedPnP,
            spin: allowHeavy ? baseFrameData.spin : nil,
            spinDrift: allowHeavy ? baseFrameData.spinDrift : nil,
            residuals: baseFrameData.residuals,
            flowVectors: baseFrameData.flowVectors
        )

        // -----------------------------
        // 8) Auto-calibration (only when PnP succeeds)
        // -----------------------------
        if allowHeavy, solvedPnP != nil {
            feedAutoCalibration(with: newFrame)
        }

        return newFrame
    }

    // ===================================================================
    // MARK: Auto-Calibration Stub
    // ===================================================================

    private func feedAutoCalibration(with frame: VisionFrameData) {
        // Reserved for V2 calibration logic.
        _ = frame
    }

    // ===================================================================
    // MARK: Helpers
    // ===================================================================

    private func intrinsicsEqual(
        lhs: (Float, Float, Float, Float)?,
        rhs: (Float, Float, Float, Float)?
    ) -> Bool {
        guard let a = lhs, let b = rhs else { return lhs == nil && rhs == nil }
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
    }
}
