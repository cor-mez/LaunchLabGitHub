//
//  FrameProfiler.swift
//  LaunchLab
//

import Foundation
import QuartzCore

final class FrameProfiler {

    static let shared = FrameProfiler()

    private struct Entry {
        var name: String
        var samples: [Double] = Array(repeating: 0, count: 120)
        var index: Int = 0
        var filled: Bool = false
    }

    private var entries: [String: Entry] = [:]
    private var frameCount: Int = 0
    private var lastGPU: GPUMetrics?

    private init() {}

    @inline(__always)
    func begin(_ name: String) -> Double {
        CACurrentMediaTime()
    }

    @inline(__always)
    func end(_ name: String, _ start: Double) {
        let dt = (CACurrentMediaTime() - start) * 1000.0
        record(name, dt)
    }

    @inline(__always)
    func recordGPU(_ metrics: GPUMetrics) {
        lastGPU = metrics
    }

    private func record(_ name: String, _ dt: Double) {
        if entries[name] == nil { entries[name] = Entry(name: name) }
        var e = entries[name]!
        e.samples[e.index] = dt
        e.index = (e.index + 1) % 120
        if e.index == 0 { e.filled = true }
        entries[name] = e
    }

    @inline(__always)
    func nextFrame() {
        frameCount += 1
        guard frameCount % 30 == 0 else { return }
        printSummary()
    }

    private func printSummary() {
        print("----- FrameProfiler (last 120 frames) -----")
        for e in entries.values.sorted(by: { $0.name < $1.name }) {
            let count = e.filled ? 120 : e.index
            guard count > 0 else { continue }
            let avg = e.samples.prefix(count).reduce(0, +) / Double(count)
            print("\(e.name): \(String(format: "%.3f", avg)) ms")
        }

        if let g = lastGPU {
            print("GPU (LK wrapper): last=\(String(format: "%.3f", g.lastDurationMS)) ms | avg=\(String(format: "%.3f", g.avgDurationMS)) ms")
        }

        print("-------------------------------------------")
    }

    // ---------------------------------------------------------
    // MARK: - HUD Metrics
    // ---------------------------------------------------------
    struct VisualMetrics {
        var detector: String
        var tracker: String
        var lk: String
        var velocity: String
        var pose: String
        var total: String
        var gpuLast: String
        var gpuAvg: String
    }

    func visualMetrics() -> VisualMetrics {
        func avg(_ name: String) -> String {
            guard let e = entries[name] else { return "0.00" }
            let count = e.filled ? 120 : e.index
            guard count > 0 else { return "0.00" }
            let avg = e.samples.prefix(count).reduce(0, +) / Double(count)
            return String(format: "%.2f", avg)
        }

        let gLast = String(format: "%.2f", lastGPU?.lastDurationMS ?? 0)
        let gAvg  = String(format: "%.2f", lastGPU?.avgDurationMS ?? 0)

        return VisualMetrics(
            detector: avg("detector"),
            tracker: avg("tracker"),
            lk: avg("lk_refiner"),
            velocity: avg("velocity"),
            pose: avg("pose"),
            total: avg("total_pipeline"),
            gpuLast: gLast,
            gpuAvg: gAvg
        )
    }
}