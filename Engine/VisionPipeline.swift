//
//  VisionPipeline.swift
//  LaunchLab
//
//  v1.5 -- Corrected & Fully Integrated
//  Pipeline:
//    FAST9 → DotTracker → LK → Cluster → BallLock → RS-Deg
//    → RSWindowBuilder → RSPnP (V1.5 SE3) → Spin → Ballistics
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
    private let rspnpSolver = RSPnPSolver()
    private let spinSolver = SpinSolver()
    private let ballisticsSolver = BallisticsSolver()

    // MARK: - Config

    private let ballLockConfig: BallLockConfig
    private var lastConfigResetFlag: Bool = false

    // MARK: - State

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

    private(set) var lastWaggleHint: WagglePlacementHint?

    // MARK: - Init

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
        rsWindowBuilder.reset()
        lastWaggleHint = nil
    }

    // MARK: - Main Entry

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        // ------------------------------------------------------------
        // Orientation / Intrinsics Change → Reset
        // ------------------------------------------------------------
        let intrSignature = (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
        if lastFrameWidth != 0 {
            if width != lastFrameWidth ||
               height != lastFrameHeight ||
               !intrinsicsEqual(lhs: intrSignature, rhs: lastIntrinsicsSignature)
            {
                reset()
            }
        }
        lastFrameWidth = width
        lastFrameHeight = height
        lastIntrinsicsSignature = intrSignature

        // ------------------------------------------------------------
        // Config Reset
        // ------------------------------------------------------------
        let configResetFlag = ballLockConfig.needsReset
        if configResetFlag != lastConfigResetFlag {
            reset()
            lastConfigResetFlag = configResetFlag
        }

        frameIndex &+= 1

        // ------------------------------------------------------------
        // Delta Time
        // ------------------------------------------------------------
        let dt: Double = prevTimestamp.map { max(0, timestamp - $0) } ?? 0
        prevTimestamp = timestamp

        // ------------------------------------------------------------
        // 1) FAST9 Detection
        // ------------------------------------------------------------
        let detections = dotDetector.detect(in: pixelBuffer)

        // ------------------------------------------------------------
        // 2) DotTracker → ID association
        // ------------------------------------------------------------
        let (trackedDots, trackingState) =
            dotTracker.track(
                detections: detections,
                previousDots: prevAllDots,
                previousState: prevTrackingState
            )

        // ------------------------------------------------------------
        // 3) LK Refinement
        // ------------------------------------------------------------
        let refinedDots: [VisionDot]
        let flows: [SIMD2<Float>]

        if let prevBuffer = prevPixelBuffer {
            let (r, f) = lkRefiner.refine(
                dots: trackedDots,
                prevBuffer: prevBuffer,
                currBuffer: pixelBuffer
            )
            refinedDots = r
            flows = f
        } else {
            refinedDots = trackedDots
            flows = []
        }

        // ------------------------------------------------------------
        // 4) Base Frame (pre-lock)
        // ------------------------------------------------------------
        var preLockFrame = VisionFrameData(
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

        // ROI for clustering
        let searchCenter = CGPoint(x: CGFloat(width) * 0.5,
                                   y: CGFloat(height) * 0.65)
        let searchRadius = min(CGFloat(width), CGFloat(height)) * 0.25

        // ------------------------------------------------------------
        // 5) BallLock + RS-gating
        // ------------------------------------------------------------
        let frameAfterLock = runBallLockStage(
            refinedDots: refinedDots,
            preLockFrame: preLockFrame,
            imageSize: imageSize,
            searchCenter: searchCenter,
            searchRadius: searchRadius,
            dt: dt,
            frameIndex: frameIndex
        )

        // ------------------------------------------------------------
        // 6) VelocityTracker on ball-only dots
        // ------------------------------------------------------------
        let velDots = velocityTracker.update(
            previousDots: prevBallDots,
            currentDots: frameAfterLock.dots,
            dt: dt
        )

        // ------------------------------------------------------------
        // 7) Final output frame
        // ------------------------------------------------------------
        let finalFrame = VisionFrameData(
            timestamp: frameAfterLock.timestamp,
            pixelBuffer: frameAfterLock.pixelBuffer,
            width: frameAfterLock.width,
            height: frameAfterLock.height,
            intrinsics: frameAfterLock.intrinsics,
            dots: velDots,
            trackingState: frameAfterLock.trackingState,
            bearings: frameAfterLock.bearings,
            correctedPoints: frameAfterLock.correctedPoints,
            rspnp: frameAfterLock.rspnp,
            spin: frameAfterLock.spin,
            spinDrift: frameAfterLock.spinDrift,
            ballRadiusPx: frameAfterLock.ballRadiusPx,
            residuals: frameAfterLock.residuals,
            flowVectors: frameAfterLock.flowVectors
        )

        // ------------------------------------------------------------
        // Update State
        // ------------------------------------------------------------
        prevAllDots = refinedDots
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevBallDots = velDots

        return finalFrame
    }

    // ========================================================================
    // MARK: - RUN: BallLock → RS → Solvers → Frame Builder
    // ========================================================================

    private func runBallLockStage(
        refinedDots: [VisionDot],
        preLockFrame: VisionFrameData,
        imageSize: CGSize,
        searchCenter: CGPoint,
        searchRadius: CGFloat,
        dt: Double,
        frameIndex: Int
    ) -> VisionFrameData {

        let cfg = ballLockConfig

        // ------------------------------------------------------------
        // 1) Classify Ball Cluster
        // ------------------------------------------------------------
        let params = BallClusterParams(
            minCorners: cfg.minCorners,
            maxCorners: cfg.maxCorners,
            minRadiusPx: CGFloat(cfg.minRadiusPx),
            maxRadiusPx: CGFloat(cfg.maxRadiusPx),
            idealRadiusMinPx: 20,
            idealRadiusMaxPx: 60,
            roiBorderMarginPx: 10,
            symmetryWeight: CGFloat(cfg.symmetryWeight),
            countWeight: CGFloat(cfg.countWeight),
            radiusWeight: CGFloat(cfg.radiusWeight)
        )

        let dotsPos = refinedDots.map { $0.position }

        let cluster = ballClusterClassifier.classify(
            dots: dotsPos,
            imageSize: imageSize,
            roiCenter: searchCenter,
            roiRadius: searchRadius,
            params: params
        )

        let clusterForLock =
            (cluster != nil && cluster!.qualityScore >= CGFloat(cfg.minQualityToEnterLock))
            ? cluster : nil

        // ------------------------------------------------------------
        // 2) BallLock state update
        // ------------------------------------------------------------
        let lock = ballLockStateMachine.update(
            cluster: clusterForLock,
            dt: dt,
            frameIndex: frameIndex,
            searchRoiCenter: searchCenter,
            searchRoiRadius: searchRadius,
            qLock: CGFloat(cfg.qLock),
            qStay: CGFloat(cfg.qStay),
            lockAfterN: cfg.lockAfterN,
            unlockAfterM: cfg.unlockAfterM,
            alphaCenter: CGFloat(cfg.alphaCenter),
            roiRadiusFactor: CGFloat(cfg.roiRadiusFactor),
            loggingEnabled: false
        )

        // ------------------------------------------------------------
        // 3) RS-Degeneracy
        // ------------------------------------------------------------
        let isPortrait = imageSize.height >= imageSize.width
        let ballPx = cluster?.radiusPx ?? 0
        let rowSpan = ballPx * 2

        // Compute shear slope
        let shearSlope: CGFloat
        if let c = cluster, let flows = preLockFrame.flowVectors, !flows.isEmpty {
            let rr = c.radiusPx * CGFloat(cfg.roiRadiusFactor)
            shearSlope = rsCalculator.estimateShearSlope(
                dots: preLockFrame.dots,
                flows: flows,
                roiCenter: c.centroid,
                roiRadius: rr
            )
        } else {
            shearSlope = 0
        }

        let rsInput = RSDegeneracyInput(
            shearSlope: shearSlope,
            rowSpanPx: rowSpan,
            blurStreakPx: 0,
            phaseRatio: 1,
            ballPx: ballPx,
            isPortrait: isPortrait
        )

        let rsResult = rsCalculator.evaluate(rsInput)

        // waggle test
        if lock.state == .searching && shearSlope > 0 {
            lastWaggleHint = rsCalculator.waggleHint(for: shearSlope)
        }

        // ------------------------------------------------------------
        // 4) Locked run
        // ------------------------------------------------------------
        lockedRunLength = lock.isLocked ? lockedRunLength + 1 : 0
        let inLockedWindow = lockedRunLength >= 3

        // ------------------------------------------------------------
        // 5) Filter dots by ROI
        // ------------------------------------------------------------
        let filteredDots: [VisionDot]
        if lock.isLocked,
           let rc = lock.roiCenter,
           let rr = lock.roiRadius {

            let r2 = rr * rr
            filteredDots = preLockFrame.dots.filter { d in
                let dx = d.position.x - rc.x
                let dy = d.position.y - rc.y
                return dx*dx + dy*dy <= r2
            }

        } else {
            filteredDots = []
        }

        // ------------------------------------------------------------
        // 6) Build locked frame BEFORE solvers (correct frame to push)
        // ------------------------------------------------------------
        var lockedFrame = VisionFrameData(
            timestamp: preLockFrame.timestamp,
            pixelBuffer: preLockFrame.pixelBuffer,
            width: preLockFrame.width,
            height: preLockFrame.height,
            intrinsics: preLockFrame.intrinsics,
            dots: filteredDots,
            trackingState: preLockFrame.trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            ballRadiusPx: cluster?.radiusPx,   // NEW--critical for RS-PnP V1.5
            residuals: preLockFrame.residuals,
            flowVectors: preLockFrame.flowVectors
        )

        // ------------------------------------------------------------
        // 7) RS WindowBuilder (use lockedFrame)
        // ------------------------------------------------------------
        let rsWindow = rsWindowBuilder.push(
            frame: lockedFrame,
            isLocked: lock.isLocked,
            clusterQuality: lock.quality,
            rsResult: rsResult,
            lockedRunLength: lockedRunLength
        )

        // ------------------------------------------------------------
        // 8) Heavy Solver Gating
        // ------------------------------------------------------------
        let allowHeavy =
            lock.isLocked &&
            lock.quality >= CGFloat(cfg.qLock) &&
            rsResult.rsConfidence >= 0.60 &&
            !rsResult.criticalDegeneracy &&
            inLockedWindow

        // ------------------------------------------------------------
        // 9) RS-PnP (V1.5)
        // ------------------------------------------------------------
        var solvedPnP: RSPnPResult? = nil
        if allowHeavy, let win = rsWindow {
            solvedPnP = rspnpSolver.solve(
                window: win,
                intrinsics: preLockFrame.intrinsics
            )
        }

        // ------------------------------------------------------------
        // 10) Spin Solver
        // ------------------------------------------------------------
        var solvedSpin: SpinResult? = nil
        if allowHeavy, let pnp = solvedPnP, let win = rsWindow, pnp.isValid {
            solvedSpin = spinSolver.solve(
                window: win,
                pnp: pnp,
                intrinsics: preLockFrame.intrinsics,
                flows: preLockFrame.flowVectors ?? []
            )
        }

        // ------------------------------------------------------------
        // 11) Ballistics Solver
        // ------------------------------------------------------------
        var solvedBallistics: BallisticsResult? = nil
        if allowHeavy, let pnp = solvedPnP, let spin = solvedSpin {
            solvedBallistics = ballisticsSolver.solve(
                pnp: pnp,
                spin: spin
            )
        }

        // ------------------------------------------------------------
        // 12) Residuals
        // ------------------------------------------------------------
        var residuals = preLockFrame.residuals ?? []

        if let rc = lock.roiCenter, let rr = lock.roiRadius {
            residuals.append(
                RPEResidual(id: 100,
                            error: SIMD2(Float(rc.x), Float(rc.y)),
                            weight: Float(rr))
            )
        }

        residuals.append(
            RPEResidual(id: 101,
                        error: SIMD2(Float(lock.quality),
                                     Float(lock.stateCode)),
                        weight: Float(rsResult.rsConfidence))
        )

        if let c = cluster {
            residuals.append(
                RPEResidual(id: 102,
                            error: SIMD2(Float(c.symmetryScore),
                                         Float(c.radiusPx)),
                            weight: Float(c.count))
            )
            residuals.append(
                RPEResidual(id: 103,
                            error: SIMD2(Float(c.countScore),
                                         Float(c.radiusScore)),
                            weight: Float(c.eccentricity))
            )
        }

        residuals.append(
            RPEResidual(id: 104,
                        error: SIMD2(Float(rsResult.shearSlope),
                                     Float(rsResult.rowSpanPx)),
                        weight: Float(rsResult.rsConfidence))
        )

        // ------------------------------------------------------------
        // 13) FINAL Locked Frame
        // ------------------------------------------------------------
        lockedFrame = VisionFrameData(
            timestamp: preLockFrame.timestamp,
            pixelBuffer: preLockFrame.pixelBuffer,
            width: preLockFrame.width,
            height: preLockFrame.height,
            intrinsics: preLockFrame.intrinsics,
            dots: filteredDots,
            trackingState: preLockFrame.trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: solvedPnP,
            spin: solvedSpin,
            spinDrift: nil,
            ballRadiusPx: cluster?.radiusPx,
            residuals: residuals,
            flowVectors: preLockFrame.flowVectors
        )

        // ------------------------------------------------------------
        // 14) AutoCalibration Hook
        // ------------------------------------------------------------
        if allowHeavy, let pnp = solvedPnP, pnp.isValid {
            feedAutoCalibration(with: lockedFrame)
        }

        return lockedFrame
    }

    // MARK: - AutoCalibration

    private func feedAutoCalibration(with frame: VisionFrameData) {
        // Placeholder
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