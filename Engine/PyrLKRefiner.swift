//
//  PyrLKRefiner.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import CoreGraphics
import UIKit
import Metal

final class PyrLKRefiner {

    private let gpu = GPUProfiler.shared

    func refine(
        prevFrame: VisionFrameData,
        currFrame: VisionFrameData,
        tracked: [VisionDot]
    ) -> [VisionDot] {

        guard !tracked.isEmpty else { return tracked }

        // -----------------------------------------------------
        // GPU TIMESTAMP PLACEHOLDER (Option A)
        // -----------------------------------------------------
        var gpuMetrics: GPUMetrics?

        if let device = gpu.device,
           let queue = gpu.queue,
           let cmd = queue.makeCommandBuffer() {

            // Enable timing
            cmd.addCompletedHandler { cb in
                let m = self.gpu.profile(commandBuffer: cb)
                gpuMetrics = m
            }

            cmd.commit()
        }

        // -----------------------------------------------------
        // CPU LK CALL
        // -----------------------------------------------------
        let prevPB = prevFrame.pixelBuffer
        let currPB = currFrame.pixelBuffer

        guard
            let prevLuma = CVPixelBufferGetBaseAddressOfPlane(prevPB, 0),
            let currLuma = CVPixelBufferGetBaseAddressOfPlane(currPB, 0)
        else {
            return tracked
        }

        let width = Int(CVPixelBufferGetWidth(prevPB))
        let height = Int(CVPixelBufferGetHeight(prevPB))
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(prevPB, 0)

        var pointsPrev = [Float]()
        pointsPrev.reserveCapacity(tracked.count * 2)
        for d in tracked {
            pointsPrev.append(Float(d.position.x))
            pointsPrev.append(Float(d.position.y))
        }

        var pointsCurr = [Float](repeating: 0, count: pointsPrev.count)
        var status = [UInt8](repeating: 0, count: tracked.count)
        var error = [Float](repeating: 0, count: tracked.count)

        ll_computePyrLKFlow(
            prevLuma.assumingMemoryBound(to: UInt8.self),
            currLuma.assumingMemoryBound(to: UInt8.self),
            Int32(width),
            Int32(height),
            Int32(bytesPerRow),
            pointsPrev,
            Int32(tracked.count),
            &pointsCurr,
            &status,
            &error
        )

        // -----------------------------------------------------
        // GPU metrics → FrameProfiler
        // -----------------------------------------------------
        if let m = gpuMetrics {
            FrameProfiler.shared.recordGPU(m)
        }

        // -----------------------------------------------------
        // Build refined output
        // -----------------------------------------------------
        var refined: [VisionDot] = []
        refined.reserveCapacity(tracked.count)

        for i in 0..<tracked.count {
            let d = tracked[i]
            if status[i] == 1 {
                let x = CGFloat(pointsCurr[i * 2 + 0])
                let y = CGFloat(pointsCurr[i * 2 + 1])
                refined.append(
                    VisionDot(
                        id: d.id,
                        position: CGPoint(x: x, y: y),
                        predicted: d.predicted,
                        velocity: d.velocity
                    )
                )
            } else {
                refined.append(d)
            }
        }

        return refined
    }
}
