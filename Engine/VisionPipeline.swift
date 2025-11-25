// File: Engine/VisionPipeline.swift
// VisionPipeline — integrates dot tracking, LK refinement, BallLock, RS-degeneracy,
// and heavy-solver gating. All shared types come from VisionTypes.swift (frozen).

import Foundation
import CoreGraphics
import CoreVideo
import simd

// MARK: - RS Degeneracy primitives (file-local)

struct RSDegeneracyParams {
    let minShearSlope: CGFloat = 0.004           // px/row
    let minRowSpanPx: CGFloat = 18.0            // global minimum row-span
    let maxPatternPhaseRatio: CGFloat = 1.6     // high-spin alias threshold
    let centralRegionRadiusPx: CGFloat = 25.0   // |centroid - principalPoint|
    let centralRowSpanCriticalPx: CGFloat = 25.0
    let symmetryCriticalSpinRpm: CGFloat = 2000.0
    let blurNonCriticalThresholdPx: CGFloat = 2.8
    let blurCriticalThresholdPx: CGFloat = 5.0
}

struct RSDegeneracyFlags {
    struct Bit {
        static let shear    = 1 << 0
        static let rowSpan  = 1 << 1
        static let alias    = 1 << 2
        static let central  = 1 << 3
        static let symmetry = 1 << 4
        static let blur     = 1 << 5
    }

    let rawValue: Int
    let hasCritical: Bool

    static let none = RSDegeneracyFlags(rawValue: 0, hasCritical: false)
}

struct RSDegeneracyInput {
    var rowSpanPx: CGFloat
    var shearSlope: CGFloat
    var patternPhaseRatio: CGFloat
    var blurStreakPx: CGFloat
    var spinRpmHint: CGFloat?
    var hasPatternSymmetry: Bool

    init(
        rowSpanPx: CGFloat,
        shearSlope: CGFloat,
        patternPhaseRatio: CGFloat,
        blurStreakPx: CGFloat,
        spinRpmHint: CGFloat? = nil,
        hasPatternSymmetry: Bool = false
    ) {
        self.rowSpanPx = rowSpanPx
        self.shearSlope = shearSlope
        self.patternPhaseRatio = patternPhaseRatio
        self.blurStreakPx = blurStreakPx
        self.spinRpmHint = spinRpmHint
        self.hasPatternSymmetry = hasPatternSymmetry
    }
}

struct RSDegeneracyResult {
    let flags: RSDegeneracyFlags
    let rsConfidence: CGFloat
}

// MARK: - VisionPipeline

final class VisionPipeline {

    // MARK: - Modules

    private let dotDetector = DotDetector()
    private let dotTracker = DotTracker()
    private let lkRefiner = PyrLKRefiner()
    private let velocityTracker = VelocityTracker()

    private let ballClusterClassifier = BallClusterClassifier()
    private let ballLockStateMachine = BallLockStateMachine()

    private let rsParams = RSDegeneracyParams()

    // MARK: - Config

    private let ballLockConfig: BallLockConfig
    private var lastConfigResetFlag: Bool = false

    // MARK: - Internal state

    // Pre-BallLock tracking dots
    private var prevAllDots: [VisionDot] = []
    private var prevTrackingState: DotTrackingState = .initial
    private var prevPixelBuffer: CVPixelBuffer?
    private var prevTimestamp: Double?

    // Post-BallLock ball dots (for velocity)
    private var prevBallDots: [VisionDot] = []

    // Trajectory window (3 locked frames)
    private var lockedRunLength: Int = 0

    // Orientation / intrinsics change detection
    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0
    private var lastIntrinsicsSignature: (Float, Float, Float, Float)?
    private var frameIndex: Int = 0

    // MARK: - Init / Reset

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

    // MARK: - Public entry from CameraManager

    /// Core per-frame entry point from CameraManager.
    /// Pipeline:
    ///   FAST9 → DotTracker → LK → BallLock → Velocity (ball-only) → VisionFrameData
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        intrinsics: CameraIntrinsics
    ) -> VisionFrameData {

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        // --------------------------------------------------------
        // Orientation / intrinsics change → auto reset BallLock
        // --------------------------------------------------------
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

        // --------------------------------------------------------
        // Config-driven soft reset (major param change)
        // --------------------------------------------------------
        let configResetFlag = ballLockConfig.needsReset
        if configResetFlag != lastConfigResetFlag {
            reset()
            lastConfigResetFlag = configResetFlag
        }

        frameIndex &+= 1

        // --------------------------------------------------------
        // dt for LK / velocity
        // --------------------------------------------------------
        let dt: Double
        if let prevTs = prevTimestamp {
            dt = max(0.0, timestamp - prevTs)
        } else {
            dt = 0.0
        }

        // --------------------------------------------------------
        // 1) FAST9 detection (raw corners in ball ROI)
        // --------------------------------------------------------
        let detections = dotDetector.detect(in: pixelBuffer)

        // --------------------------------------------------------
        // 2) DotTracker — ID association
        // --------------------------------------------------------
        let (trackedDots, trackingState) = dotTracker.track(
            detections: detections,
            previousDots: prevAllDots,
            previousState: prevTrackingState
        )

        // --------------------------------------------------------
        // 3) PyrLK refinement (prev → curr) on tracked dots
        // --------------------------------------------------------
        let refinedTrackingDots: [VisionDot]
        let flows: [SIMD2<Float>]

        if let prevBuffer = prevPixelBuffer {
            let (refined, flow) = lkRefiner.refine(
                dots: trackedDots,
                prevBuffer: prevBuffer,
                currBuffer: pixelBuffer
            )
            refinedTrackingDots = refined
            flows = flow
        } else {
            refinedTrackingDots = trackedDots
            flows = []
        }

        // --------------------------------------------------------
        // 4) Prepare base frame BEFORE BallLock
        // --------------------------------------------------------
        let baseFramePreLock = VisionFrameData(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            intrinsics: intrinsics,
            dots: refinedTrackingDots,
            trackingState: trackingState,
            bearings: nil,
            correctedPoints: nil,
            rspnp: nil,
            spin: nil,
            spinDrift: nil,
            residuals: nil,
            flowVectors: flows
        )

        // --------------------------------------------------------
        // 5) RS-degeneracy inputs (placeholder for now)
        // --------------------------------------------------------
        let rsInput = RSDegeneracyInput(
            rowSpanPx: 0,
            shearSlope: 0,
            patternPhaseRatio: 0,
            blurStreakPx: 0
        )

        let principalPoint = CGPoint(
            x: CGFloat(intrinsics.cx),
            y: CGFloat(intrinsics.cy)
        )

        // Coarse search ROI: align with DotDetector ROI (lower-center).
        let searchRoiCenter = CGPoint(
            x: CGFloat(width) * 0.5,
            y: CGFloat(height) * 0.65
        )
        let searchRoiRadius = min(CGFloat(width), CGFloat(height)) * 0.25

        // --------------------------------------------------------
        // 6) BallLock + RS gating (runs right after LK)
        // --------------------------------------------------------
        let frameAfterBallLock = runBallLockStage(
            refinedDots: refinedTrackingDots,
            imageSize: imageSize,
            searchRoiCenter: searchRoiCenter,
            searchRoiRadius: searchRoiRadius,
            rsInput: rsInput,
            principalPoint: principalPoint,
            baseFrameData: baseFramePreLock,
            dt: dt,
            frameIndex: frameIndex
        )

        // After BallLock, frameAfterBallLock.dots is:
        //   • ball-only when locked
        //   • [] when not locked

        // --------------------------------------------------------
        // 7) VelocityTracker on ball-only dots (post-lock)
        // --------------------------------------------------------
        let ballDotsWithVelocity = velocityTracker.update(
            previousDots: prevBallDots,
            currentDots: frameAfterBallLock.dots,
            dt: dt
        )

        // Build final frame with velocities on ball dots.
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
            residuals: frameAfterBallLock.residuals,
            flowVectors: frameAfterBallLock.flowVectors
        )

        // --------------------------------------------------------
        // 8) Update internal state for next frame
        // --------------------------------------------------------
        prevAllDots = refinedTrackingDots
        prevTrackingState = trackingState
        prevPixelBuffer = pixelBuffer
        prevTimestamp = timestamp
        prevBallDots = ballDotsWithVelocity

        return finalFrame
    }

    // MARK: - BallLock + RS-gating stage (internal)

    private func runBallLockStage(
        refinedDots: [VisionDot],
        imageSize: CGSize,
        searchRoiCenter: CGPoint,
        searchRoiRadius: CGFloat,
        rsInput: RSDegeneracyInput,
        principalPoint: CGPoint,
        baseFrameData: VisionFrameData,
        dt: Double,
        frameIndex: Int
    ) -> VisionFrameData {

        let cfg = ballLockConfig

        // Build classifier params from config
        let params = BallClusterParams(
            minCorners: cfg.minCorners,
            maxCorners: cfg.maxCorners,
            minRadiusPx: CGFloat(cfg.minRadiusPx),
            maxRadiusPx: CGFloat(cfg.maxRadiusPx),
            idealRadiusMinPx: 20.0,
            idealRadiusMaxPx: 60.0,
            roiBorderMarginPx: 10.0,
            symmetryScale: 1.5,
            symmetryWeight: CGFloat(cfg.symmetryWeight),
            countWeight: CGFloat(cfg.countWeight),
            radiusWeight: CGFloat(cfg.radiusWeight)
        )

        // Use LK-refined positions for clustering.
        var positions: [CGPoint] = []
        positions.reserveCapacity(refinedDots.count)
        for d in refinedDots {
            positions.append(d.position)
        }

        // 1) Ball cluster classification inside search ROI using refined LK dots.
        let cluster = ballClusterClassifier.classify(
            dots: positions,
            imageSize: imageSize,
            roiCenter: searchRoiCenter,
            roiRadius: searchRoiRadius,
            params: params
        )

        // Only clusters above minQualityToEnterLock are allowed to drive BallLock.
        let clusterForLock: BallCluster?
        if let c = cluster,
           c.qualityScore >= CGFloat(cfg.minQualityToEnterLock) {
            clusterForLock = c
        } else {
            clusterForLock = nil
        }

        // 2) Ball lock state update.
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
            loggingEnabled: cfg.showBallLockLogging
        )

        // 3) RS-degeneracy checks (before heavy RS-PnP).
        let rsResult = evaluateRSDegeneracy(
            input: rsInput,
            ballCentroid: cluster?.centroid,
            principalPoint: principalPoint
        )

        // 4) Trajectory frame window — require 3 consecutive locked frames.
        if lockOutput.isLocked {
            if lockedRunLength < Int.max {
                lockedRunLength += 1
            }
        } else {
            lockedRunLength = 0
        }
        let inLockedWindow = lockedRunLength >= 3

        // 5) Filter VisionDots by locked ROI when locked; empty array when not locked.
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
        } else {
            filteredDots = []
        }

        // 6) Gating for heavy RS-PnP / Spin.
        let allowHeavySolvers =
            lockOutput.isLocked &&
            lockOutput.quality >= CGFloat(cfg.qLock) &&
            rsResult.rsConfidence >= 0.60 &&
            !rsResult.flags.hasCritical &&
            inLockedWindow

        // Gate existing heavy-solver outputs (if any) from upstream.
        let gatedRspnp: RSPnPResult?          = allowHeavySolvers ? baseFrameData.rspnp : nil
        let gatedSpin: SpinResult?            = allowHeavySolvers ? baseFrameData.spin : nil
        let gatedSpinDrift: SpinDriftMetrics? = allowHeavySolvers ? baseFrameData.spinDrift : nil

        // 7) BallLock residuals for debug overlay.
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

        // Cluster metrics residual (symmetry, radius, count)
        if let c = cluster {
            let metricsResidual = RPEResidual(
                id: 102,
                error: SIMD2<Float>(
                    Float(c.symmetryScore),
                    Float(c.radiusPx)
                ),
                weight: Float(c.count)
            )
            residuals.append(metricsResidual)

            // Optional eccentricity residual for future HUD/overlay tuning.
            let eccResidual = RPEResidual(
                id: 103,
                error: SIMD2<Float>(
                    Float(c.eccentricity),
                    0
                ),
                weight: 1
            )
            residuals.append(eccResidual)
        }

        // 8) Build new immutable VisionFrameData.
        let newFrame = VisionFrameData(
            timestamp: baseFrameData.timestamp,
            pixelBuffer: baseFrameData.pixelBuffer,
            width: baseFrameData.width,
            height: baseFrameData.height,
            intrinsics: baseFrameData.intrinsics,
            dots: filteredDots,
            trackingState: baseFrameData.trackingState,
            bearings: baseFrameData.bearings,
            correctedPoints: baseFrameData.correctedPoints,
            rspnp: gatedRspnp,
            spin: gatedSpin,
            spinDrift: gatedSpinDrift,
            residuals: residuals,
            flowVectors: baseFrameData.flowVectors
        )

        // 9) AutoCalibration: only locked frames with valid PnP.
        if allowHeavySolvers, newFrame.rspnp != nil {
            feedAutoCalibration(with: newFrame)
        }

        return newFrame
    }

    // MARK: - AutoCalibration hook

    private func feedAutoCalibration(with frame: VisionFrameData) {
        // Hook into existing AutoCalibration subsystem here.
        _ = frame
    }

    // MARK: - RS degeneracy evaluation

    private func evaluateRSDegeneracy(
        input: RSDegeneracyInput,
        ballCentroid: CGPoint?,
        principalPoint: CGPoint
    ) -> RSDegeneracyResult {
        var rawValue = 0
        var hasCritical = false
        var confidence: CGFloat = 1.0

        // Shear degeneracy.
        if abs(input.shearSlope) < rsParams.minShearSlope {
            rawValue |= RSDegeneracyFlags.Bit.shear
            hasCritical = true
        }

        // Row-span degeneracy (global).
        if input.rowSpanPx < rsParams.minRowSpanPx {
            rawValue |= RSDegeneracyFlags.Bit.rowSpan
            hasCritical = true
        }

        // High-spin alias.
        if input.patternPhaseRatio > rsParams.maxPatternPhaseRatio {
            rawValue |= RSDegeneracyFlags.Bit.alias
            hasCritical = true
        }

        // Central-ray ambiguity.
        if let centroid = ballCentroid {
            let dx = centroid.x - principalPoint.x
            let dy = centroid.y - principalPoint.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= rsParams.centralRegionRadiusPx {
                if input.rowSpanPx < rsParams.centralRowSpanCriticalPx {
                    rawValue |= RSDegeneracyFlags.Bit.central
                    hasCritical = true
                } else {
                    rawValue |= RSDegeneracyFlags.Bit.central
                    confidence -= 0.20
                }
            }
        }

        // Symmetry degeneracy.
        if input.hasPatternSymmetry {
            rawValue |= RSDegeneracyFlags.Bit.symmetry
            if let spin = input.spinRpmHint,
               spin > rsParams.symmetryCriticalSpinRpm {
                hasCritical = true
            } else {
                confidence -= 0.15
            }
        }

        // Exposure-blur degeneracy.
        if input.blurStreakPx > rsParams.blurNonCriticalThresholdPx {
            rawValue |= RSDegeneracyFlags.Bit.blur
            if input.blurStreakPx > rsParams.blurCriticalThresholdPx {
                hasCritical = true
            } else {
                confidence -= 0.15
            }
        }

        if confidence < 0 {
            confidence = 0
        } else if confidence > 1 {
            confidence = 1
        }

        let flags = RSDegeneracyFlags(
            rawValue: rawValue,
            hasCritical: hasCritical
        )
        return RSDegeneracyResult(
            flags: flags,
            rsConfidence: confidence
        )
    }

    // MARK: - Helpers

    private func intrinsicsEqual(
        lhs: (Float, Float, Float, Float)?,
        rhs: (Float, Float, Float, Float)?
    ) -> Bool {
        guard let a = lhs, let b = rhs else { return lhs == nil && rhs == nil }
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3
    }
}
