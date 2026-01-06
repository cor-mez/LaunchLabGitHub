//
//  RollingShutterSessionStats.swift
//  LaunchLab
//
//  Measurement-only running baseline + z-score utilities.
//  No authority. No gating decisions.
//
//  Use:
//    - feed "quiet" frames first to build baseline
//    - then compute z-scores for subsequent frames
//

import Foundation

struct RSFeatureSample {
    let slope: Double
    let r2: Double
    let nonu: Double
    let lw: Double
    let edge: Double
    let rawCount: Double
    let filtCount: Double
}

struct RSZScoreSample {
    let zSlope: Double
    let zR2: Double
    let zNonu: Double
    let zLW: Double
    let zEdge: Double
    let zRaw: Double
    let zFilt: Double

    var maxAbs: Double {
        return max(
            abs(zSlope),
            abs(zR2),
            abs(zNonu),
            abs(zLW),
            abs(zEdge),
            abs(zRaw),
            abs(zFilt)
        )
    }
}

// Simple Welford running mean/variance
private struct RunningStats {
    private(set) var n: Int = 0
    private(set) var mean: Double = 0
    private var m2: Double = 0

    mutating func reset() {
        n = 0
        mean = 0
        m2 = 0
    }

    mutating func add(_ x: Double) {
        n += 1
        let delta = x - mean
        mean += delta / Double(n)
        let delta2 = x - mean
        m2 += delta * delta2
    }

    var variance: Double {
        guard n >= 2 else { return 0 }
        return m2 / Double(n - 1)
    }

    var std: Double {
        return sqrt(max(variance, 1e-9))
    }
}

final class RollingShutterSessionStats {

    // Baseline stats
    private var slope = RunningStats()
    private var r2 = RunningStats()
    private var nonu = RunningStats()
    private var lw = RunningStats()
    private var edge = RunningStats()
    private var raw = RunningStats()
    private var filt = RunningStats()

    // How many baseline frames collected?
    var baselineCount: Int { slope.n }

    func resetBaseline() {
        slope.reset()
        r2.reset()
        nonu.reset()
        lw.reset()
        edge.reset()
        raw.reset()
        filt.reset()
    }

    func addBaseline(_ s: RSFeatureSample) {
        slope.add(s.slope)
        r2.add(s.r2)
        nonu.add(s.nonu)
        lw.add(s.lw)
        edge.add(s.edge)
        raw.add(s.rawCount)
        filt.add(s.filtCount)
    }

    func hasBaseline(minCount: Int) -> Bool {
        return baselineCount >= minCount
    }

    func zScores(for s: RSFeatureSample) -> RSZScoreSample? {
        guard baselineCount >= 2 else { return nil }

        func z(_ x: Double, _ st: RunningStats) -> Double {
            (x - st.mean) / st.std
        }

        return RSZScoreSample(
            zSlope: z(s.slope, slope),
            zR2: z(s.r2, r2),
            zNonu: z(s.nonu, nonu),
            zLW: z(s.lw, lw),
            zEdge: z(s.edge, edge),
            zRaw: z(s.rawCount, raw),
            zFilt: z(s.filtCount, filt)
        )
    }

    // Useful for logs/UI
    func baselineSummary() -> String {
        guard baselineCount >= 2 else { return "baseline n=\(baselineCount)" }

        func fmt(_ name: String, _ st: RunningStats) -> String {
            String(format: "%@ μ=%.4f σ=%.4f", name, st.mean, st.std)
        }

        return [
            "baseline n=\(baselineCount)",
            fmt("slope", slope),
            fmt("r2", r2),
            fmt("nonu", nonu),
            fmt("lw", lw),
            fmt("edge", edge),
            fmt("raw", raw),
            fmt("filt", filt)
        ].joined(separator: " | ")
    }
}
