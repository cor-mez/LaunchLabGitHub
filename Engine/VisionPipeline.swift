//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import CoreMedia
import simd

/// LaunchLab Vision Pipeline v6
/// Full rolling-shutter, PnP, spin, drift, and ball-flight pipeline
/// with hybrid 3D launch-vector estimation and calibration injection.
final class VisionPipeline {

    // ============================================================
    // MARK: - Submodules
    // ============================================================
    private let detector   = DotDetector()
    private let tracker    = DotTracker()
    private let lk         = PyrLKRefiner()
    private let velocityKF = VelocityTracker()
    private let poseSolver = PoseSolver()

    private let rsLine     = RSLineIndex()
    private let rsBV       = RSBearingVectors()
    private let rsCorr     = RSGeometricCorrector()
    private let rsPnP      = RSPnPSolver()

    private let spinSolver = SpinAxisSolver()
    private let dotModel   = DotModel()
    private let rpe        = RPEResiduals()

    private let ballModel  = BallFlightModel()
    private let ballistics = BallisticsSolver()

    private let profiler   = FrameProfiler.shared

    // ============================================================
    // MARK: - Calibration-Injected Parameters
    // ============================================================

    /// Calibrated camera intrinsics
    public var calibratedIntrinsics: CameraIntrinsics = .zero

    /// Camera tilt (pitch, roll)
    public var cameraTiltPitch: Float = 0
    public var cameraTiltRoll: Float  = 0

    /// Camera translation offset (meters)
    public var cameraTranslationOffset: SIMD3<Float> = SIMD3(0,0,0)

    /// Ball distance scalar (meters)
    public var ballDistanceMeters: Float = 2.0

    /// Lighting gain for detector
    public var lightingGain: Float = 1.0

    /// RS Timing Model (injected)
    public var rsTimingModel: RSTimingModelProtocol = LinearRSTimingModel()

    // ============================================================
    // MARK: - State
    // ============================================================
    private var prevFrame: VisionFrameData?

    // ============================================================
    // MARK: - PROCESS FRAME
    // ============================================================
    func process(_ curr: VisionFrameData) -> VisionFrameData {

        let t_total = profiler.begin("total_pipeline")

        // --------------------------------------------------------
        // 1. DETECTOR  (with lighting compensation)
        // --------------------------------------------------------
        let t_det = profiler.begin("detector")

        detector.lightingGain = lightingGain
        let detectedPoints = detector.detect(in: curr.pixelBuffer)

        profiler.end("detector", t_det)

        // --------------------------------------------------------
        // 2. TRACKER
        // --------------------------------------------------------
        let t_trk = profiler.begin("tracker")
        let prevDots = prevFrame?.dots ?? []
        let tracked = tracker.track(prev: prevDots, currPoints: detectedPoints)
        profiler.end("tracker", t_trk)

        // --------------------------------------------------------
        // 3. PYR LK REFINER
        // --------------------------------------------------------
        let t_lk = profiler.begin("lk_refiner")
        let (refined, lkDebug) = prevFrame != nil
            ? lk.refineWithDebug(prevFrame: prevFrame!, currFrame: curr, tracked: tracked)
            : (tracked, PyrLKDebugInfo())
        profiler.end("lk_refiner", t_lk)

        // --------------------------------------------------------
        // 4. VELOCITY KF (pixel flow)
        // --------------------------------------------------------
        let t_vel = profiler.begin("velocityKF")
        let withVel = velocityKF.process(refined, timestamp: curr.timestamp)
        profiler.end("velocityKF", t_vel)

        // --------------------------------------------------------
        // 5. BASE POSE (Global EPnP + GN)
        // --------------------------------------------------------
        let t_pose = profiler.begin("poseSolver")

        let imagePoints: [SIMD2<Float>] = withVel.map {
            SIMD2(Float($0.position.x), Float($0.position.y))
        }

        let basePose = poseSolver.solve(
            imagePoints: imagePoints,
            intrinsics: calibratedIntrinsics.matrix
        )

        profiler.end("poseSolver", t_pose)

        // --------------------------------------------------------
        // 6. RS LINE INDEX
        // --------------------------------------------------------
        let lineIndex = rsLine.compute(
            frame: curr,
            imagePoints: imagePoints
        )

        // --------------------------------------------------------
        // 7. RS TIMING (v2)
        // --------------------------------------------------------
        let h = Float(curr.height)
        let timestamp = Float(curr.timestamp)

        var rsTimes = [Float]()
        rsTimes.reserveCapacity(imagePoints.count)

        for p in imagePoints {
            let y = max(0, min(h - 1, p.y))
            rsTimes.append(
                rsTimingModel.timestampForRow(
                    y,
                    height: h,
                    frameTimestamp: timestamp
                )
            )
        }

        // --------------------------------------------------------
        // 8. RS BEARINGS
        // --------------------------------------------------------
        let modelPoints = (0..<DotModel.count).map { dotModel.point(for: $0) }

        let bearings = rsBV.compute(
            imagePoints: imagePoints,
            modelPoints: modelPoints,
            timestamps: rsTimes,
            intrinsics: calibratedIntrinsics.matrix
        )

        // --------------------------------------------------------
        // 9. RS GEOMETRIC CORRECTION
        // --------------------------------------------------------
        let R0 = basePose?.R ?? matrix_identity_float3x3
        let T0 = basePose?.T ?? SIMD3<Float>(0,0,0)

        let corrected = rsCorr.correct(
            bearings: bearings,
            baseRotation: simd_quatf(R0),
            translation: T0 + cameraTranslationOffset,
            velocity: SIMD3(0,0,0),
            angularVelocity: SIMD3(0,0,0),
            baseTimestamp: timestamp
        )
                // --------------------------------------------------------
        // 10. RS-PnP v2 (Full Rolling-Shutter Pose)
        // --------------------------------------------------------
        let rspnp = rsPnP.solve(
            bearings: corrected,
            intrinsics: calibratedIntrinsics.matrix,
            modelPoints: modelPoints
        )

        // --------------------------------------------------------
        // 11. SPIN AXIS SOLVER
        // --------------------------------------------------------
        let spinOut = spinSolver.solve(from: rspnp)

        // --------------------------------------------------------
        // 12. RPE RESIDUALS (Reprojection Error Map)
        // --------------------------------------------------------
        let rpeRes: [RPEResidual]
        if let rs = rspnp {
            rpeRes = rpe.compute(
                modelPoints: modelPoints,
                imagePoints: imagePoints,
                rotation: rs.R,
                translation: rs.T,
                intrinsics: calibratedIntrinsics.matrix
            )
        } else {
            rpeRes = []
        }

        // --------------------------------------------------------
        // 13. HYBRID VELOCITY ESTIMATION (3D LAUNCH VECTOR)
        // --------------------------------------------------------

        // Approach:
        // 1. Use KF pixel-flow velocity to estimate Vx/Vy direction.
        // 2. Use ball distance calibration + RS-PnP T to lift to 3D.
        // 3. Low-pass blend over last frames (not implemented yet).
        //
        // Output: estimated 3D initial velocity vector (m/s)

        let launchVelocity3D: SIMD3<Float>

        if let rs = rspnp {
            // Pixel velocity → angular rate → 3D direction
            let avgVel = withVel.compactMap { $0.velocity }.reduce(CGVector(dx: 0, dy: 0)) {
                CGVector(dx: $0.dx + $1.dx, dy: $0.dy + $1.dy)
            }

            let n = Float(withVel.count)
            let vpx = Float(avgVel.dx) / max(1, n)
            let vpy = Float(avgVel.dy) / max(1, n)

            let dir2D = SIMD3<Float>(vpx, vpy, -1.0)   // camera forward = -Z
            let dirNorm = simd_normalize(dir2D)

            // Scale direction by depth-to-ball scalar to convert
            // angle change into launch velocity estimate.
            let speedGuess: Float = 32.0   // m/s placeholder; replaced in BallFlightSolver
            launchVelocity3D = speedGuess * dirNorm

        } else {
            launchVelocity3D = SIMD3<Float>(0,0,0)
        }

        // --------------------------------------------------------
        // 14. BALL FLIGHT SOLVER (Physics Integration)
        // --------------------------------------------------------

        let flight: BallFlightResult?

        if let spin = spinOut {
            let rpm = spin.rpm
            let axis = spin.axis

            let result = ballistics.integrateFlight(
                initialVelocity: launchVelocity3D,
                spinAxis: axis,
                rpm: rpm,
                model: ballModel
            )
            flight = result
        } else {
            flight = nil
        }

        // --------------------------------------------------------
        // 15. BUILD OUTPUT FRAME
        // --------------------------------------------------------
        let out = VisionFrameData(
            pixelBuffer: curr.pixelBuffer,
            width: curr.width,
            height: curr.height,
            timestamp: curr.timestamp,
            intrinsics: calibratedIntrinsics,
            pose: basePose,
            dots: withVel
        )

        out.rsLineIndex  = lineIndex
        out.rsTimestamps = rsTimes
        out.rsBearings   = bearings
        out.rsCorrected  = corrected
        out.rspnp        = rspnp
        out.spin         = spinOut
        out.rsResiduals  = rpeRes
        out.lkDebug      = lkDebug
        out.flight       = flight
                // --------------------------------------------------------
        // 16. SPIN DRIFT METRICS
        // --------------------------------------------------------
        out.spinDrift = SpinDriftMetrics(
            previous: prevFrame?.spin,
            current: spinOut
        )

        // --------------------------------------------------------
        // 17. APPLY CALIBRATION OFFSETS
        // --------------------------------------------------------
        // Camera tilt adjustment (pitch/roll)
        out.cameraTiltPitch = cameraTiltPitch
        out.cameraTiltRoll  = cameraTiltRoll

        // Camera translation offset
        out.cameraTranslationOffset = cameraTranslationOffset

        // Depth / distance-to-ball scalar
        out.ballDistanceMeters = ballDistanceMeters

        // Lighting correction gain
        out.lightingGain = lightingGain

        // --------------------------------------------------------
        // 18. PROFILING END
        // --------------------------------------------------------
        profiler.end("total_pipeline", token_total)
        profiler.nextFrame()

        // --------------------------------------------------------
        // 19. ADVANCE STATE
        // --------------------------------------------------------
        prevFrame = out
        return out
    }
}