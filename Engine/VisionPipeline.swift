// File: Engine/VisionPipeline.swift
//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

final class VisionPipeline {

    // MARK: - Modules

    private let dotDetector = DotDetector()
    private let dotTracker = DotTracker()
    private let lkRefiner = PyrLKRefiner()
    private let velocityTracker = VelocityTracker()

    private let ballClusterClassifier = BallClusterClassifier()
    private let ballLockStateMachine = BallLockStateMachine()

    private let rsCalculator = RSDegeneracyCalculator()
    private let rsWindowBuilder = RSWindowBuilder()
    private let flickerAnalyzer = FlickerAnalyzer()

    private let rspnpSolver = RSPnPSolver()
    private let spinSolver = SpinSolver()

    // MARK: - Config

    private let ballLockConfig: BallLockConfig
    private var lastConfigResetFlag: Bool = false

    // MARK: - Runtime state

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

    private var lastStableCluster: BallCluster?
    private var smoothedBallRadiusPx: CGFloat = 0

    private(set) var lastWaggleHint: WagglePlacementHint?

    var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    // MARK: - Init / Reset

    init(ballLockConfig: BallLockConfig) {
        self.ballLockConfig = ballLockConfig
        reset()
    }

    func reset() {
        ballLockStateMachine.reset()
        rsWindowBuilder.reset()
        lockedRunLength = 0
        prevAllDots = []
        prevTrackingState = .initial
        prevPixelBuffer = nil
        prevTimestamp = nil
        prevBallDots = []
        lastFrameWidth = 0
        lastFrameHeight = 0
        lastIntrinsicsSignature = nil
        frameIndex = 0
        lastStableCluster = nil
        smoothedBallRadiusPx = 0
        lastWaggleHint = nil
    }

    // MARK: - Public entry

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics,
        imuState: IMUState
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        let flicker = flickerAnalyzer.evaluate(pixelBuffer: pixelBuffer)

        let intrSignature = (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
        if lastFrameWidth != 0 {
            if width != lastFrameWidth ||
               height != lastFrameHeight ||
               !intrinsicsEqual(lhs: intrSignature, rhs: lastIntrinsicsSignature) {
                reset()
            }
        }
        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsicsSignature = intrSignature

        let configResetFlag = ballLockConfig.needsReset
        if configResetFlag != lastConfigResetFlag {
            reset()
            lastConfigResetFlag = configResetFlag
        }

        frameIndex &+= 1

        let dt: Double
        if let prevTs = prevTimestamp {
            dt = max(0.0, timestamp - prevTs)
        } else {
            dt = 0.0
        }
        prevTimestamp = timestamp

        let detections = dotDetector.detect(in: pixelBuffer)

        let (trackedDots, trackingState) = dotTracker.track(
            detections: detections,
            previousDots: prevAllDots,
            previousState: prevTrackingState
        )

        let refinedDots: [VisionDot]
        let flows: [SIMD2<Float>]

        if let prevBuffer = prevPixelBuffer {
            let (refined, flow) = lkRefiner.refine(
                dots: trackedDots,
                prevBuffer: prevBuffer,
                currBuffer: pixelBuffer
            )
            refinedDots = refined
            flows = flow
        } else {
            refinedDots = trackedDots
            flows = []
        }

        let baseFramePreLock = VisionFrameData(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            dots: refinedDots,
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

        let principalPoint = CGPoint(
            x: CGFloat(intrinsics.cx),
            y: CGFloat(intrinsics.cy)
        )

        let searchRoiCenter = CGPoint(
            x: CGFloat(width) * 0.5,
            y: CGFloat(height) * 0.65
        )
        let searchRoiRadius = min(CGFloat(width), CGFloat(height)) * 0.25

        let frameAfterBallLock = runBallLockStage(
            refinedDots: refinedDots,
            imageSize: imageSize,
            searchRoiCenter: searchRoiCenter,
            searchRoiRadius: searchRoiRadius,
            baseFrameData: baseFramePreLock,
            dt: dt,
            frameIndex: frameIndex,
            principalPoint: principalPoint,
            flicker: flicker,
            imuState: imuState
        )

        let ballDotsWithVelocity = velocityTracker.update(
            previousDots: prevBallDots,
            currentDots: frameAfterBallLock.dots,
            dt: dt
        )

        let finalFrame = VisionFrameData(
            timestamp: frameAfterBallLock.timestamp,
            pixelBuffer: frameAfterBallLock.pixelBuffer,
            width: frameAfterBallLock.width,
            height: frameAfterBallLock.height,
            intrinsics: frameAfterBallLock.intrinsics,
            dots: ballDotsWithVelocity,
            trackingState: frameAfterBallLock.trackingState,
            bearings: frameAfterBallLock.bearings,
            correctedPoints: frameAfterBallLock.correctedPoints,
            rspnp: frameAfterBallLock.rspnp,
            spin: frameAfterBallLock.spin,
            spinDrift: frameAfterBallLock.spinDrift,
            ballRadiusPx: frameAfterBallLock.ballRadiusPx,
            residuals: frameAfterBallLock.residuals,
            flowVectors: frameAfterBallLock.flowVectors
        )

        prevAllDots = refinedDots
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevBallDots = ballDotsWithVelocity

        return finalFrame
    }

    // MARK: - BallLock + RS + Heavy

    private func runBallLockStage(
        refinedDots: [VisionDot],
        imageSize: CGSize,
        searchRoiCenter: CGPoint,
        searchRoiRadius: CGFloat,
        baseFrameData: VisionFrameData,
        dt: Double,
        frameIndex: Int,
        principalPoint: CGPoint,
        flicker: FlickerMetrics,
        imuState: IMUState
    ) -> VisionFrameData {

        let cfg = ballLockConfig

        let params = BallClusterParams(
            minCorners: cfg.minCorners,
            maxCorners: cfg.maxCorners,
            minRadiusPx: CGFloat(cfg.minRadiusPx),
            maxRadiusPx: CGFloat(cfg.maxRadiusPx),
            idealRadiusMinPx: 20.0,
            idealRadiusMaxPx: 60.0,
            roiBorderMarginPx: 10.0,
            symmetryWeight: CGFloat(cfg.symmetryWeight),
            countWeight: CGFloat(cfg.countWeight),
            radiusWeight: CGFloat(cfg.radiusWeight)
        )

        var positions: [CGPoint] = []
        positions.reserveCapacity(refinedDots.count)
        for d in refinedDots {
            positions.append(d.position)
        }

        let rawCluster = ballClusterClassifier.classify(
            dots: positions,
            imageSize: imageSize,
            roiCenter: searchRoiCenter,
            roiRadius: searchRoiRadius,
            params: params
        )

        var effectiveCluster: BallCluster? = rawCluster
        if !flicker.isDimPhase {
            if let c = rawCluster {
                lastStableCluster = c
            }
        } else {
            if let stable = lastStableCluster {
                effectiveCluster = stable
            } else {
                effectiveCluster = nil
            }
        }

        let clusterForLock: BallCluster?
        if let c = effectiveCluster,
           c.qualityScore >= CGFloat(cfg.minQualityToEnterLock) {
            clusterForLock = c
        } else {
            clusterForLock = nil
        }

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
            loggingEnabled: false,
            suppressFlicker: flicker.isDimPhase
        )

        let isPortrait: Bool = {
            let g = imuState.gravity
            let gNorm = simd_length(g) > 0 ? simd_normalize(g) : SIMD3<Float>(0, -1, 0)
            let aligned = abs(gNorm.y) > 0.7
            return aligned
        }()

        let ballPx: CGFloat = effectiveCluster?.radiusPx ?? 0.0
        let rowSpanPx: CGFloat = max(0.0, ballPx * 2.0)

        let shearSlope: CGFloat
        if let centroid = effectiveCluster?.centroid,
           let flows = baseFrameData.flowVectors,
           !flows.isEmpty {
            let roiRadiusForShear = (effectiveCluster?.radiusPx ?? searchRoiRadius) * CGFloat(cfg.roiRadiusFactor)
            shearSlope = rsCalculator.estimateShearSlope(
                dots: baseFrameData.dots,
                flows: flows,
                roiCenter: centroid,
                roiRadius: roiRadiusForShear
            )
        } else {
            shearSlope = 0.0
        }

        let blurStreakPx: CGFloat = 0.0
        let phaseRatio: CGFloat = 1.0

        let rsInput = RSDegeneracyInput(
            shearSlope: shearSlope,
            rowSpanPx: rowSpanPx,
            blurStreakPx: blurStreakPx,
            phaseRatio: phaseRatio,
            ballPx: ballPx,
            isPortrait: isPortrait,
            flickerModulation: CGFloat(flicker.flickerModulation)
        )

        let rsResult = rsCalculator.evaluate(
            rsInput,
            isFlickerUnsafe: flicker.isFlickerUnsafe
        )

        if lockOutput.state == .searching, shearSlope > 0 {
            lastWaggleHint = rsCalculator.waggleHint(for: shearSlope)
        }

        if lockOutput.isLocked {
            if lockedRunLength < Int.max {
                lockedRunLength += 1
            }
        } else {
            lockedRunLength = 0
        }

        let allDots = baseFrameData.dots
        var filteredDots: [VisionDot] = []

        if lockOutput.isLocked,
           let roiCenter = lockOutput.roiCenter,
           let roiRadius = lockOutput.roiRadius {
            let radiusSq = roiRadius * roiRadius
            filteredDots.reserveCapacity(allDots.count)
            for dot in allDots {
                let dx = dot.position.x - roiCenter.x
                let dy = dot.position.y - roiCenter.y
                if dx * dx + dy * dy <= radiusSq {
                    filteredDots.append(dot)
                }
            }
        }

        var ballRadiusPxSmoothed: CGFloat? = nil
        if let c = effectiveCluster {
            let alpha: CGFloat = 0.15
            if smoothedBallRadiusPx <= 0 {
                smoothedBallRadiusPx = c.radiusPx
            } else {
                let invAlpha: CGFloat = 1.0 - alpha
                smoothedBallRadiusPx = smoothedBallRadiusPx * invAlpha + c.radiusPx * alpha
            }
            ballRadiusPxSmoothed = smoothedBallRadiusPx
        }

        var residuals: [RPEResidual] = baseFrameData.residuals ?? []

        if let roiCenter = lockOutput.roiCenter,
           let roiRadius = lockOutput.roiRadius {
            let roiResidual = RPEResidual(
                id: 100,
                error: SIMD2<Float>(
                    Float(roiCenter.x),
                    Float(roiCenter.y)
                ),
                weight: Float(roiRadius)
            )
            residuals.append(roiResidual)
        }

        let qualityResidual = RPEResidual(
            id: 101,
            error: SIMD2<Float>(
                Float(lockOutput.quality),
                Float(lockOutput.stateCode)
            ),
            weight: Float(rsResult.rsConfidence)
        )
        residuals.append(qualityResidual)

        if let c = effectiveCluster {
            let metricsResidual = RPEResidual(
                id: 102,
                error: SIMD2<Float>(
                    Float(c.symmetryScore),
                    Float(c.radiusPx)
                ),
                weight: Float(c.count)
            )
            residuals.append(metricsResidual)

            let scoresResidual = RPEResidual(
                id: 103,
                error: SIMD2<Float>(
                    Float(c.countScore),
                    Float(c.radiusScore)
                ),
                weight: Float(c.eccentricity)
            )
            residuals.append(scoresResidual)
        }

        let rsResidual = RPEResidual(
            id: 104,
            error: SIMD2<Float>(
                Float(rsResult.shearSlope),
                Float(rsResult.rowSpanPx)
            ),
            weight: Float(rsResult.rsConfidence)
        )
        residuals.append(rsResidual)

        let preHeavyFrame = VisionFrameData(
            timestamp: baseFrameData.timestamp,
            pixelBuffer: baseFrameData.pixelBuffer,
            width: baseFrameData.width,
            height: baseFrameData.height,
            intrinsics: baseFrameData.intrinsics,
            dots: filteredDots,
            trackingState: baseFrameData.trackingState,
            bearings: baseFrameData.bearings,
            correctedPoints: baseFrameData.correctedPoints,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            ballRadiusPx: ballRadiusPxSmoothed,
            residuals: residuals,
            flowVectors: baseFrameData.flowVectors
        )

        let rsWindow = rsWindowBuilder.push(
            frame: preHeavyFrame,
            isLocked: lockOutput.isLocked,
            clusterQuality: lockOutput.quality,
            rsResult: rsResult,
            lockedRunLength: lockedRunLength
        )

        let allowHeavyRS =
            lockOutput.isLocked &&
            lockOutput.quality >= CGFloat(cfg.qLock) &&
            rsResult.rsConfidence >= 0.60 &&
            !rsResult.criticalDegeneracy &&
            !flicker.isFlickerUnsafe &&
            lockedRunLength >= 3 &&
            rsWindow != nil

        let thermalOK = thermalState != .serious && thermalState != .critical
        let finalAllowHeavy = allowHeavyRS && thermalOK

        let rsGateCode: Float
        if !lockOutput.isLocked ||
            lockOutput.quality < CGFloat(cfg.qLock) ||
            lockedRunLength < 3 ||
            rsWindow == nil {
            rsGateCode = 4
        } else if rsResult.criticalDegeneracy || rsResult.rsConfidence < 0.60 {
            rsGateCode = 2
        } else if flicker.isFlickerUnsafe {
            rsGateCode = 3
        } else if !thermalOK {
            rsGateCode = 5
        } else {
            rsGateCode = 1
        }

        let gateResidual = RPEResidual(
            id: 105,
            error: SIMD2<Float>(
                rsGateCode,
                Float(flicker.flickerModulation)
            ),
            weight: Float(rsResult.rsConfidence)
        )
        residuals.append(gateResidual)

        var solvedPnP: RSPnPResult? = nil
        if finalAllowHeavy, let win = rsWindow {
            solvedPnP = rspnpSolver.solve(
                window: win,
                intrinsics: baseFrameData.intrinsics,
                rowGradient: flicker.rowGradient
            )
        }

        var solvedSpin: SpinResult? = nil
        if finalAllowHeavy,
           let pnp = solvedPnP,
           pnp.isValid,
           let win = rsWindow {
            solvedSpin = spinSolver.solve(
                window: win,
                pnp: pnp,
                intrinsics: baseFrameData.intrinsics,
                flows: baseFrameData.flowVectors ?? []
            )
        }

        let lockedFrame = VisionFrameData(
            timestamp: baseFrameData.timestamp,
            pixelBuffer: baseFrameData.pixelBuffer,
            width: baseFrameData.width,
            height: baseFrameData.height,
            intrinsics: baseFrameData.intrinsics,
            dots: filteredDots,
            trackingState: baseFrameData.trackingState,
            bearings: baseFrameData.bearings,
            correctedPoints: baseFrameData.correctedPoints,
            rspnp: solvedPnP,
            spin: solvedSpin,
            spinDrift: nil,
            ballRadiusPx: ballRadiusPxSmoothed,
            residuals: residuals,
            flowVectors: baseFrameData.flowVectors
        )

        if finalAllowHeavy, let pnp = solvedPnP, pnp.isValid {
            feedAutoCalibration(with: lockedFrame)
        }

        return lockedFrame
    }

    // MARK: - AutoCalibration

    private func feedAutoCalibration(with frame: VisionFrameData) {
        _ = frame
    }

    // MARK: - Helpers

    private func intrinsicsEqual(
        lhs: (Float, Float, Float, Float)?,
        rhs: (Float, Float, Float, Float)?
    ) -> Bool {
        guard let a = lhs, let b = rhs else { return false }
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
    }
}
