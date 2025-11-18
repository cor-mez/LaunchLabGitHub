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

    private var lastFrame: VisionFrameData?

    func process(_ curr: VisionFrameData) -> VisionFrameData {

        let prev = lastFrame
        let t_total = profiler.begin("total_pipeline")

        // 1. DETECTOR
        let t_det = profiler.begin("detector")
        let detectedPoints = detector.detect(in: curr.pixelBuffer)
        profiler.end("detector", t_det)

        // 2. TRACKER
        let t_trk = profiler.begin("tracker")
        let tracked = tracker.track(prev: prev?.dots ?? [], currPoints: detectedPoints)
        profiler.end("tracker", t_trk)

        // 3. LK REFINER (wrapped in GPU timing)
        let t_lk = profiler.begin("lk_refiner")
        let refined = prev != nil
            ? lk.refine(prevFrame: prev!, currFrame: curr, tracked: tracked)
            : tracked
        profiler.end("lk_refiner", t_lk)

        // 4. VELOCITY
        let t_vel = profiler.begin("velocity")
        let withVelocity = velocity.process(refined, timestamp: curr.timestamp)
        profiler.end("velocity", t_vel)

        // 5. POSE
        let t_pose = profiler.begin("pose")
        let imagePoints = withVelocity.map { SIMD2(Float($0.position.x), Float($0.position.y)) }
        let poseOut = pose.solve(imagePoints: imagePoints, intrinsics: curr.intrinsics.matrix)
        profiler.end("pose", t_pose)

        profiler.end("total_pipeline", t_total)
        profiler.nextFrame()

        // Build next frame
        let out = VisionFrameData(
            pixelBuffer: curr.pixelBuffer,
            width: curr.width,
            height: curr.height,
            timestamp: curr.timestamp,
            intrinsics: curr.intrinsics,
            pose: poseOut,
            dots: withVelocity
        )

        lastFrame = out
        return out
    }
}
