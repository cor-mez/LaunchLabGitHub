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

    private let detector = DotDetector()
    private let tracker = DotTracker()
    private let lk = PyrLKRefiner()
    private let velocity = VelocityTracker()
    private let pose = PoseSolver()
    private let profiler = FrameProfiler.shared

    private let rspnp = RSPnPSolver()
    private let rsTiming = RSTimingModel()
    private let rsBV = RSBearingVectors()
    private let rsLine = RSLineIndex()
    private let rsCorr = RSGeometricCorrector()

    private let dotModel = DotModel()

    func process(prev: VisionFrameData?, curr: VisionFrameData) -> VisionFrameData {

        let t_total = profiler.begin("total_pipeline")

        // 1. DETECTOR
        let t_det = profiler.begin("detector")
        let detectedPoints = detector.detect(in: curr.pixelBuffer)
        profiler.end("detector", t_det)

        // 2. TRACKER
        let t_trk = profiler.begin("tracker")
        let prevDots = prev?.dots ?? []
        let tracked = tracker.track(prev: prevDots, currPoints: detectedPoints)
        profiler.end("tracker", t_trk)

        // 3. PYR LK
        let t_lk = profiler.begin("lk_refiner")
        let refined = prev != nil
            ? lk.refine(prevFrame: prev!, currFrame: curr, tracked: tracked)
            : tracked
        profiler.end("lk_refiner", t_lk)

        // 4. VELOCITY KF
        let t_vel = profiler.begin("velocity")
        let withVel = velocity.process(refined, timestamp: curr.timestamp)
        profiler.end("velocity", t_vel)

        // 5. POSE SOLVER
        let t_pose = profiler.begin("pose")
        let imagePoints = withVel.map {
            SIMD2<Float>(Float($0.position.x), Float($0.position.y))
        }
        let poseOut = pose.solve(
            imagePoints: imagePoints,
            intrinsics: curr.intrinsics.matrix
        )
        profiler.end("pose", t_pose)

        // 6. RS LINE INDICES
        let lineIndex = rsLine.compute(
            frame: curr,
            imagePoints: imagePoints
        )

        // 7. RS TIMING
        let rsTimes = rsTiming.computeDotTimes(
            frame: curr,
            dotPositions: imagePoints
        )

        // 8. RS BEARINGS
        let modelPoints = (0..<DotModel.count).map { dotModel.point(for: $0) }
        let bearings = rsBV.compute(
            imagePoints: imagePoints,
            modelPoints: modelPoints,
            timestamps: rsTimes,
            intrinsics: curr.intrinsics.matrix
        )

        // -----------------------------------------------------
        // 9. RS GEOMETRIC CORRECTION (v1.5)
        // -----------------------------------------------------
        let baseRot = poseOut?.R.toQuaternion ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0,1,0))
        let baseT   = poseOut?.T ?? SIMD3<Float>(0,0,0)
        let v       = SIMD3<Float>(0,0,0) // translational velocity placeholder
        let w       = SIMD3<Float>(0,0,0) // angular velocity placeholder
        let ts0     = Float(curr.timestamp)

        let corrected = rsCorr.correct(
            bearings: bearings,
            baseRotation: baseRot,
            translation: baseT,
            velocity: v,
            angularVelocity: w,
            baseTimestamp: ts0
        )

        // 10. RS-PnP Stub
        let rspnpResult = rspnp.solve(
            frame: curr,
            modelPoints: modelPoints,
            imagePoints: imagePoints,
            timestamps: rsTimes
        )

        // 11. BUILD FRAME
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

        profiler.end("total_pipeline", t_total)
        profiler.nextFrame()

        return out
    }
}