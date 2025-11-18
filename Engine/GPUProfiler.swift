//
//  GPUProfiler.swift
//  LaunchLab
//

import Foundation
import Metal

struct GPUMetrics {
    var lastDurationMS: Double = 0
    var avgDurationMS: Double = 0
}

final class GPUProfiler {

    static let shared = GPUProfiler()

    private var samples: [Double] = Array(repeating: 0, count: 120)
    private var index: Int = 0
    private var filled = false

    private init() {}

    // Metal handles
    let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    lazy var queue: MTLCommandQueue? = {
        device?.makeCommandQueue()
    }()

    @discardableResult
    func profile(commandBuffer: MTLCommandBuffer) -> GPUMetrics {

        let start = commandBuffer.gpuStartTime
        let end = commandBuffer.gpuEndTime

        guard start > 0, end > 0 else {
            return GPUMetrics(lastDurationMS: 0, avgDurationMS: average())
        }

        let dt = (end - start) * 1000.0

        samples[index] = dt
        index = (index + 1) % 120
        if index == 0 { filled = true }

        return GPUMetrics(lastDurationMS: dt, avgDurationMS: average())
    }

    private func average() -> Double {
        let count = filled ? 120 : index
        guard count > 0 else { return 0 }
        let sum = samples.prefix(count).reduce(0, +)
        return sum / Double(count)
    }
}
