//
//  VisionPipeline.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import CoreMedia
import QuartzCore
import simd

final class VisionPipeline {

    // ---------------------------------------------------------
    // MARK: - Submodules
    // ---------------------------------------------------------
    private let detector = DotDetector()
    private let tracker = DotTracker()
    private let lk = PyrLKRefiner()
    private let velocity = VelocityTracker()
    private let pose = PoseSolver()

    private let profiler = FrameProfiler.shared

    private let rsLine = RSLineIndex()
    private let rsTiming = RSTimingModel()
    private let rsBV = RSBearingVectors()
    private let rsCorr = RSGeometricCorrector()
    private let rsPnP = RSPnPSolver()

    private let spinSolver = SpinAxisSolver()

    private let dotModel = DotModel()

    // ---------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------
    private var prevFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Main Entry
    // ---------------------------------------------------------
    func process(_ curr: VisionFrameData) -> VisionFrameData {

        let t_total = profiler.begin("total_pipeline")

        // 1. DETECTOR
        let t_det = profiler.begin("detector")
        let detectedPoints = detector.detect(in: curr.pixelBuffer)
        profiler.end("detector", t_det)

        // 2. TRACKER
        let t_trk = profiler.begin("tracker")
        let prevDots = prevFrame?.dots ?? []
        let tracked = tracker.track(prev: prevDots, currPoints: detectedPoints)
        profiler.end("tracker", t_trk)

        // 3. PYR LK
        let t_lk = profiler.begin("lk_refiner")
        let refined = prevFrame != nil
            ? lk.refine(prevFrame: prevFrame!, currFrame: curr, tracked: tracked)
            : tracked
        profiler.end("lk_refiner", t_lk)

        // 4. VELOCITY KF
        let t_vel = profiler.begin("velocity")
        let withVel = velocity.process(refined, timestamp: curr.timestamp)
        profiler.end("velocity", t_vel)

        // 5. BASE POSE
        let t_pose = profiler.begin("pose")
        let imagePoints = withVel.map {
            SIMD2<Float>(Float($0.position.x), Float($0.position.y))
        }
        let poseOut = pose.solve(
            imagePoints: imagePoints,
            intrinsics: curr.intrinsics.matrix
        )
        profiler.end("pose", t_pose)

        // 6. RS LINE INDEX
        let lineIndex = rsLine.compute(frame: curr, imagePoints: imagePoints)

        // 7. RS TIMING
        let rsTimes = rsTiming.computeDotTimes(frame: curr, dotPositions: imagePoints)

        // 8. RS BEARINGS
        let modelPoints = (0..<DotModel.count).map { dotModel.point(for: $0) }
        let bearings = rsBV.compute(
            imagePoints: imagePoints,
            modelPoints: modelPoints,
            timestamps: rsTimes,
            intrinsics: curr.intrinsics.matrix
        )

        // 9. RS CORRECTION (v1.5)
        let baseR = poseOut?.R ?? simd_float3x3(diagonal: SIMD3<Float>(1,1,1))
        let baseT = poseOut?.T ?? SIMD3<Float>(0,0,0)
        let corrected = rsCorr.correct(
            bearings: bearings,
            baseRotation: simd_quatf(baseR),
            translation: baseT,
            velocity: SIMD3<Float>(0,0,0),
            angularVelocity: SIMD3<Float>(0,0,0),
            baseTimestamp: Float(curr.timestamp)
        )

        // 10. RS-PnP v2 SOLVER
        let rspnpResult = rsPnP.solve(
            corrected: corrected,
            intrinsics: curr.intrinsics.matrix,
            modelPoints: modelPoints
        )

        // 11. SPIN SOLVER
        let spinOut = spinSolver.solve(from: rspnpResult)

        // 12. BUILD OUTPUT FRAME
        let out = VisionFrameData(
            pixelBuffer: curr.pixelBuffer,
            width: curr.width,
            height: curr.height,
            timestamp: curr.timestamp,
            intrinsics: curr.intrinsics,
            pose: poseOut,
            dots: withVel
        )

        out.rsLineIndex = lineIndex
        out.rsTimestamps = rsTimes
        out.rsBearings = bearings
        out.rsCorrected = corrected
        out.rspnp = rspnpResult
        out.spin = spinOut

        profiler.end("total_pipeline", t_total)
        profiler.nextFrame()

        prevFrame = out
        return out
    }
}