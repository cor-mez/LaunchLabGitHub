//ImpactCenteredDynamicObservabilityModule.swift//
import Foundation
import simd

// MARK: - Config

public struct ImpactCenteredDynamicObservabilityConfig: Equatable {
    public var enabled: Bool

    /// Max samples retained for context + baseline.
    public var historySize: Int

    /// Frames used to build "pre-impact" baseline for robust scoring.
    public var baselineFrames: Int

    /// Frames before the peak included in the impact window (event slice).
    public var preFrames: Int

    /// Frames after the peak included in the impact window (event slice).
    public var postFrames: Int

    /// Offset from peak used for pre/post geometry + confidence comparisons.
    public var compareOffsetFrames: Int

    /// Candidate is considered "notable" if its score ranks at or above this percentile
    /// when compared against the pre-impact baseline distribution (dynamic, not absolute).
    public var minCandidatePercentile: Double

    /// Require at least this many signals to be available (non-nil) for a candidate to be considered.
    public var minSignalsRequired: Int

    /// Prevent spamming multiple windows for a single physical event.
    public var minFramesBetweenCandidates: Int

    /// Avoid dumping extremely long scanline profiles into logs.
    public var maxScanlineProfilePrintCount: Int

    public init(
        enabled: Bool = true,
        historySize: Int = 240,
        baselineFrames: Int = 40,
        preFrames: Int = 6,
        postFrames: Int = 6,
        compareOffsetFrames: Int = 2,
        minCandidatePercentile: Double = 0.98,
        minSignalsRequired: Int = 2,
        minFramesBetweenCandidates: Int = 12,
        maxScanlineProfilePrintCount: Int = 48
    ) {
        self.enabled = enabled
        self.historySize = max(60, historySize)
        self.baselineFrames = max(10, baselineFrames)
        self.preFrames = max(1, preFrames)
        self.postFrames = max(1, postFrames)
        self.compareOffsetFrames = max(1, compareOffsetFrames)
        self.minCandidatePercentile = min(max(minCandidatePercentile, 0.0), 1.0)
        self.minSignalsRequired = max(1, minSignalsRequired)
        self.minFramesBetweenCandidates = max(1, minFramesBetweenCandidates)
        self.maxScanlineProfilePrintCount = max(8, maxScanlineProfilePrintCount)

        // Ensure history is large enough to hold baseline + window context.
        let minNeeded = self.baselineFrames + self.preFrames + self.postFrames + 10
        if self.historySize < minNeeded {
            self.historySize = minNeeded
        }
    }
}

// MARK: - Observation Input

/// A single per-frame observational snapshot.
/// This module is intentionally agnostic: pass what you have, nil the rest.
///
/// IMPORTANT: This module does not emit pose or spin and does not feed downstream.
/// It only logs impact-adjacent observables for later analysis.
public struct ICDOObservation {
    public let nowSec: Double

    /// Preferred if you have a real frame counter. If nil, the module will auto-index.
    public let frameIndex: Int?

    /// Optional centroid in pixel coordinates (post ROI / tracking).
    public let centroidPx: SIMD2<Double>?

    /// Optional scalar motion estimate (px/sec). If nil but centroid is present,
    /// the module will compute speed from centroid deltas.
    public let motionPxPerSec: Double?

    /// Optional FAST9 feature displacement estimate (px) for this frame (or this frame vs previous).
    /// If you already have a reliable "rapid FAST9 displacement" signal, pass it here.
    public let featureMeanDispPx: Double?

    /// Optional feature count / density proxy (e.g., afterDensity, ballLockIn).
    public let densityCount: Int?

    /// Optional geometry metrics (from MDG or precomputed).
    public let compactness: Double?
    public let radiusPx: Double?

    /// Optional RS-specific observables (if you have them upstream).
    public let rsShear: Double?
    public let rsTemporalAsymmetry: Double?
    public let scanlineMotionProfile: [Double]?

    /// Confidence + continuity signals (observational only).
    public let ballLockConfidence: Float?
    public let mdgAccepted: Bool?
    public let rsWindowValid: Bool?

    public init(
        nowSec: Double,
        frameIndex: Int? = nil,
        centroidPx: SIMD2<Double>? = nil,
        motionPxPerSec: Double? = nil,
        featureMeanDispPx: Double? = nil,
        densityCount: Int? = nil,
        compactness: Double? = nil,
        radiusPx: Double? = nil,
        rsShear: Double? = nil,
        rsTemporalAsymmetry: Double? = nil,
        scanlineMotionProfile: [Double]? = nil,
        ballLockConfidence: Float? = nil,
        mdgAccepted: Bool? = nil,
        rsWindowValid: Bool? = nil
    ) {
        self.nowSec = nowSec
        self.frameIndex = frameIndex
        self.centroidPx = centroidPx
        self.motionPxPerSec = motionPxPerSec
        self.featureMeanDispPx = featureMeanDispPx
        self.densityCount = densityCount
        self.compactness = compactness
        self.radiusPx = radiusPx
        self.rsShear = rsShear
        self.rsTemporalAsymmetry = rsTemporalAsymmetry
        self.scanlineMotionProfile = scanlineMotionProfile
        self.ballLockConfidence = ballLockConfidence
        self.mdgAccepted = mdgAccepted
        self.rsWindowValid = rsWindowValid
    }
}

// MARK: - Module

public final class ImpactCenteredDynamicObservabilityModule {

    // MARK: - Types

    private struct Sample {
        let nowSec: Double
        let frame: Int

        let centroidPx: SIMD2<Double>?
        let speedPxPerSec: Double?
        let speedAccelPxPerSec2: Double?

        let centroidVelPxPerSec: SIMD2<Double>?
        let centroidAccelPxPerSec2: SIMD2<Double>?
        let centroidAccelMagPxPerSec2: Double?

        let featureMeanDispPx: Double?

        let densityCount: Int?
        let densityDeltaAbs: Double?

        let compactness: Double?
        let radiusPx: Double?

        let rsShearAbs: Double?
        let rsTemporalAsymAbs: Double?
        let scanlineMotionProfile: [Double]?

        let ballLockConfidence: Float?
        let mdgAccepted: Bool?
        let rsWindowValid: Bool?

        /// Lightweight score series to find local peaks (computed against a rolling baseline).
        let combinedScore: Double?
    }

    private enum Metric: String, CaseIterable {
        case centroidAccel = "centroid_accel"
        case speedAccel = "speed_accel"
        case fast9Disp = "fast9_disp"
        case densityTopology = "density_topology"
        case rsShear = "rs_shear"
        case rsTemporalAsym = "rs_temporal_asym"
    }

    private struct MetricScore {
        let metric: Metric
        let z: Double
    }

    private struct PendingCandidate {
        let peakIndex: Int       // index into samples[]
        let triggers: [MetricScore]
        let percentile: Double
        let score: Double
    }

    // MARK: - State

    private let cfg: ImpactCenteredDynamicObservabilityConfig

    private var autoFrame = 0
    private var samples: [Sample] = []

    private var pending: PendingCandidate?
    private var lastCandidateFrame: Int?

    public init(config: ImpactCenteredDynamicObservabilityConfig = .init()) {
        self.cfg = config
    }

    // MARK: - Public API

    /// Call once per frame after your existing truth gates (post-detection / post-MDG / post-static-pose),
    /// before any spin or dynamic-pose logic.
    public func observe(_ obs: ICDOObservation) {
        guard cfg.enabled else { return }

        let frame = obs.frameIndex ?? autoFrame
        if obs.frameIndex == nil { autoFrame += 1 }

        let prev = samples.last
        let dt = safeDt(prevNow: prev?.nowSec, now: obs.nowSec)

        // Velocity from centroid (vector), if available.
        var centroidVel: SIMD2<Double>? = nil
        if let c = obs.centroidPx, let pc = prev?.centroidPx, let dt {
            centroidVel = (c - pc) / dt
        }

        // Speed (scalar): prefer supplied motion, else derive from centroid.
        var speed: Double? = obs.motionPxPerSec
        if speed == nil, let v = centroidVel {
            speed = simd_length(v)
        }

        // Speed acceleration (scalar), if speed is available.
        var speedAccel: Double? = nil
        if let s = speed, let ps = prev?.speedPxPerSec, let dt {
            speedAccel = abs(s - ps) / dt
        }

        // Centroid acceleration (vector), if velocity is available.
        var centroidAccel: SIMD2<Double>? = nil
        if let v = centroidVel, let pv = prev?.centroidVelPxPerSec, let dt {
            centroidAccel = (v - pv) / dt
        }
        let centroidAccelMag = centroidAccel.map { simd_length($0) }

        // Density topology change (absolute delta).
        var densityDeltaAbs: Double? = nil
        if let d = obs.densityCount, let pd = prev?.densityCount {
            densityDeltaAbs = Double(abs(d - pd))
        }

        let rsShearAbs = obs.rsShear.map { abs($0) }
        let rsTemporalAsymAbs = obs.rsTemporalAsymmetry.map { abs($0) }

        // Compute a lightweight combined score for peak finding (robust z-score against rolling baseline).
        let provisional = Sample(
            nowSec: obs.nowSec,
            frame: frame,
            centroidPx: obs.centroidPx,
            speedPxPerSec: speed,
            speedAccelPxPerSec2: speedAccel,
            centroidVelPxPerSec: centroidVel,
            centroidAccelPxPerSec2: centroidAccel,
            centroidAccelMagPxPerSec2: centroidAccelMag,
            featureMeanDispPx: obs.featureMeanDispPx,
            densityCount: obs.densityCount,
            densityDeltaAbs: densityDeltaAbs,
            compactness: obs.compactness,
            radiusPx: obs.radiusPx,
            rsShearAbs: rsShearAbs,
            rsTemporalAsymAbs: rsTemporalAsymAbs,
            scanlineMotionProfile: obs.scanlineMotionProfile,
            ballLockConfidence: obs.ballLockConfidence,
            mdgAccepted: obs.mdgAccepted,
            rsWindowValid: obs.rsWindowValid,
            combinedScore: nil
        )

        let score = computeRollingCombinedScore(adding: provisional)
        let sample = Sample(
            nowSec: provisional.nowSec,
            frame: provisional.frame,
            centroidPx: provisional.centroidPx,
            speedPxPerSec: provisional.speedPxPerSec,
            speedAccelPxPerSec2: provisional.speedAccelPxPerSec2,
            centroidVelPxPerSec: provisional.centroidVelPxPerSec,
            centroidAccelPxPerSec2: provisional.centroidAccelPxPerSec2,
            centroidAccelMagPxPerSec2: provisional.centroidAccelMagPxPerSec2,
            featureMeanDispPx: provisional.featureMeanDispPx,
            densityCount: provisional.densityCount,
            densityDeltaAbs: provisional.densityDeltaAbs,
            compactness: provisional.compactness,
            radiusPx: provisional.radiusPx,
            rsShearAbs: provisional.rsShearAbs,
            rsTemporalAsymAbs: provisional.rsTemporalAsymAbs,
            scanlineMotionProfile: provisional.scanlineMotionProfile,
            ballLockConfidence: provisional.ballLockConfidence,
            mdgAccepted: provisional.mdgAccepted,
            rsWindowValid: provisional.rsWindowValid,
            combinedScore: score
        )

        append(sample)
        finalizePendingIfReady()
        detectPeakCandidateIfAny()
    }

    // MARK: - Candidate Detection (event-based)

    /// Detect local maxima in the per-frame combinedScore series.
    /// When a peak is observed, evaluate it as a "candidate impact window" (not impact detection).
    private func detectPeakCandidateIfAny() {
        guard pending == nil else { return }
        guard samples.count >= 3 else { return }

        let i0 = samples.count - 3
        let i1 = samples.count - 2 // peak candidate index
        let i2 = samples.count - 1

        guard
            let s0 = samples[i0].combinedScore,
            let s1 = samples[i1].combinedScore,
            let s2 = samples[i2].combinedScore
        else { return }

        // Local maximum (event-like) without any smoothing.
        guard s1 > s0, s1 > s2 else { return }

        // Avoid repeated candidates too close together.
        if let last = lastCandidateFrame {
            if abs(samples[i1].frame - last) < cfg.minFramesBetweenCandidates {
                return
            }
        }

        // Evaluate this peak using a pre-impact baseline distribution.
        guard let eval = evaluatePeak(at: i1) else {
            // Ambiguous / insufficient baseline context -> allowed refusal.
            log("[IMPACT] candidate refused reason=insufficient_baseline frame=\(samples[i1].frame)")
            return
        }

        // Require multi-signal availability (not a single threshold).
        let availableSignals = eval.triggers.count
        guard availableSignals >= cfg.minSignalsRequired else {
            log("[IMPACT] candidate refused reason=insufficient_signals frame=\(samples[i1].frame) signals=\(availableSignals)")
            return
        }

        // Percentile-based (dynamic) notability gate (still just a *candidate* window).
        guard eval.percentile >= cfg.minCandidatePercentile else {
            log(
                "[IMPACT] candidate refused reason=low_percentile frame=\(samples[i1].frame) " +
                "pct=\(fmtPct(eval.percentile)) score=\(fmt(eval.score))"
            )
            return
        }

        // Hold as pending until we have postFrames available for pre/during/post logging.
        pending = PendingCandidate(
            peakIndex: i1,
            triggers: eval.triggers,
            percentile: eval.percentile,
            score: eval.score
        )
    }

    private func finalizePendingIfReady() {
        guard let p = pending else { return }

        // Ensure we still have the peak in buffer (history trimming can invalidate).
        guard p.peakIndex >= 0, p.peakIndex < samples.count else {
            log("[IMPACT] candidate refused reason=history_truncated")
            pending = nil
            return
        }

        // Wait until postFrames exist.
        let neededEnd = p.peakIndex + cfg.postFrames
        guard neededEnd < samples.count else { return }

        let peak = samples[p.peakIndex]

        let startIndex = max(0, p.peakIndex - cfg.preFrames)
        let endIndex = min(samples.count - 1, p.peakIndex + cfg.postFrames)

        let start = samples[startIndex]
        let end = samples[endIndex]
        let spanMs = (end.nowSec - start.nowSec) * 1000.0

        // REQUIRED LOGS (candidate window definition)
        log("[IMPACT] candidate start frame=\(start.frame)")
        log("[IMPACT] candidate span_ms=\(fmt(spanMs))")
        log("[IMPACT] trigger signals=\(fmtTriggers(p.triggers)) pct=\(fmtPct(p.percentile)) score=\(fmt(p.score))")

        // REQUIRED LOGS (RS signature logging)
        let shearPeak = maxAbs(in: samples[startIndex...endIndex], key: { $0.rsShearAbs })
        let asymPeak = maxAbs(in: samples[startIndex...endIndex], key: { $0.rsTemporalAsymAbs })
        log("[RS] shear_peak=\(fmt(shearPeak))")
        log("[RS] temporal_asymmetry=\(fmt(asymPeak))")
        log("[RS] scanline_motion_profile=\(fmtProfile(peak.scanlineMotionProfile))")

        // REQUIRED LOGS (pre/during/post geometry comparison)
        let preIdx = max(0, p.peakIndex - cfg.compareOffsetFrames)
        let postIdx = min(samples.count - 1, p.peakIndex + cfg.compareOffsetFrames)

        let pre = samples[preIdx]
        let post = samples[postIdx]

        log(
            "[IMPACT][GEOM] pre compactness=\(fmt(pre.compactness)) " +
            "during compactness=\(fmt(peak.compactness)) " +
            "post compactness=\(fmt(post.compactness))"
        )

        // Additional geometry observables (still logs only; no thresholds/acceptance)
        log(
            "[IMPACT][GEOM] pre radius=\(fmt(pre.radiusPx)) " +
            "during radius=\(fmt(peak.radiusPx)) " +
            "post radius=\(fmt(post.radiusPx))"
        )
        log(
            "[IMPACT][GEOM] pre density=\(fmtInt(pre.densityCount)) " +
            "during density=\(fmtInt(peak.densityCount)) " +
            "post density=\(fmtInt(post.densityCount))"
        )

        // Motion direction consistency (optional but requested)
        let dirConsDeg = directionConsistencyDeg(pre: pre, mid: peak, post: post)
        log("[IMPACT][GEOM] motion_dir_consistency_deg=\(fmt(dirConsDeg))")

        // REQUIRED LOGS (confidence behavior)
        log(
            "[IMPACT][CONF] pre=\(fmt(pre.ballLockConfidence)) " +
            "during=\(fmt(peak.ballLockConfidence)) " +
            "post=\(fmt(post.ballLockConfidence)) " +
            "mdg=\(fmtBoolTriplet(pre.mdgAccepted, peak.mdgAccepted, post.mdgAccepted)) " +
            "window=\(fmtBoolTriplet(pre.rsWindowValid, peak.rsWindowValid, post.rsWindowValid))"
        )

        // Mark candidate complete
        lastCandidateFrame = peak.frame
        pending = nil
    }

    // MARK: - Peak Evaluation (baseline percentile + triggers)

    private func evaluatePeak(at peakIndex: Int) -> (percentile: Double, score: Double, triggers: [MetricScore])? {
        guard peakIndex > 0 else { return nil }

        let baselineStart = max(0, peakIndex - cfg.baselineFrames)
        let baselineRange = baselineStart..<peakIndex
        guard baselineRange.count >= 10 else { return nil }

        // Build per-metric baseline value arrays.
        var baselineValues: [Metric: [Double]] = [:]
        for m in Metric.allCases { baselineValues[m] = [] }

        for i in baselineRange {
            for m in Metric.allCases {
                if let v = metricValue(m, at: i) {
                    baselineValues[m, default: []].append(v)
                }
            }
        }

        // Stats per metric (median + MAD-based scale).
        var stats: [Metric: (median: Double, scale: Double)] = [:]
        for m in Metric.allCases {
            guard let vals = baselineValues[m], vals.count >= 6 else { continue }
            guard let med = median(vals) else { continue }
            let s = max(mad(vals, med), 1e-6)
            stats[m] = (median: med, scale: s)
        }

        // Require at least 2 metrics to have valid baselines.
        guard stats.count >= 2 else { return nil }

        // Peak z-scores and triggers.
        var peakMetricScores: [MetricScore] = []
        var peakScoreSum = 0.0

        for (m, st) in stats {
            guard let v = metricValue(m, at: peakIndex) else { continue }
            let z = abs(v - st.median) / st.scale
            if z.isFinite, z > 0 {
                peakMetricScores.append(.init(metric: m, z: z))
                peakScoreSum += z
            }
        }

        // Require multi-signal availability.
        guard peakMetricScores.count >= cfg.minSignalsRequired else { return nil }

        // Baseline score distribution (computed using the SAME stats for fair percentile).
        var baselineScores: [Double] = []
        baselineScores.reserveCapacity(baselineRange.count)

        for i in baselineRange {
            var sum = 0.0
            for (m, st) in stats {
                guard let v = metricValue(m, at: i) else { continue }
                let z = abs(v - st.median) / st.scale
                if z.isFinite, z > 0 { sum += z }
            }
            baselineScores.append(sum)
        }

        guard baselineScores.count >= 10 else { return nil }
        let pct = percentile(of: peakScoreSum, comparedTo: baselineScores)

        // Triggers: keep top metrics by z (transparent).
        let triggers = peakMetricScores.sorted(by: { $0.z > $1.z })

        return (percentile: pct, score: peakScoreSum, triggers: triggers)
    }

    private func metricValue(_ m: Metric, at i: Int) -> Double? {
        guard i >= 0, i < samples.count else { return nil }
        let s = samples[i]
        switch m {
        case .centroidAccel:
            return s.centroidAccelMagPxPerSec2
        case .speedAccel:
            return s.speedAccelPxPerSec2
        case .fast9Disp:
            return s.featureMeanDispPx
        case .densityTopology:
            return s.densityDeltaAbs
        case .rsShear:
            return s.rsShearAbs
        case .rsTemporalAsym:
            return s.rsTemporalAsymAbs
        }
    }

    // MARK: - Rolling Combined Score (for peak detection only)

    /// Compute a rolling "combinedScore" for the new sample vs a baseline from recent history.
    /// This is NOT impact detection. It exists only to find local maxima (event-like moments).
    private func computeRollingCombinedScore(adding newSample: Sample) -> Double? {
        // Use baseline from existing samples only (pre-newSample).
        guard !samples.isEmpty else { return nil }

        let end = samples.count
        let start = max(0, end - cfg.baselineFrames)
        let baseline = samples[start..<end]
        guard baseline.count >= 10 else { return nil }

        // Build baseline arrays per metric.
        var arrays: [Metric: [Double]] = [:]
        for m in Metric.allCases { arrays[m] = [] }

        for s in baseline {
            if let v = s.centroidAccelMagPxPerSec2 { arrays[.centroidAccel, default: []].append(v) }
            if let v = s.speedAccelPxPerSec2 { arrays[.speedAccel, default: []].append(v) }
            if let v = s.featureMeanDispPx { arrays[.fast9Disp, default: []].append(v) }
            if let v = s.densityDeltaAbs { arrays[.densityTopology, default: []].append(v) }
            if let v = s.rsShearAbs { arrays[.rsShear, default: []].append(v) }
            if let v = s.rsTemporalAsymAbs { arrays[.rsTemporalAsym, default: []].append(v) }
        }

        var score = 0.0
        var used = 0

        for (m, vals) in arrays {
            guard vals.count >= 6 else { continue }
            guard let med = median(vals) else { continue }
            let scale = max(mad(vals, med), 1e-6)

            let v: Double?
            switch m {
            case .centroidAccel: v = newSample.centroidAccelMagPxPerSec2
            case .speedAccel: v = newSample.speedAccelPxPerSec2
            case .fast9Disp: v = newSample.featureMeanDispPx
            case .densityTopology: v = newSample.densityDeltaAbs
            case .rsShear: v = newSample.rsShearAbs
            case .rsTemporalAsym: v = newSample.rsTemporalAsymAbs
            }

            guard let vv = v else { continue }
            let z = abs(vv - med) / scale
            if z.isFinite {
                score += z
                used += 1
            }
        }

        guard used >= 2 else { return nil }
        return score
    }

    // MARK: - Append + Trim

    private func append(_ s: Sample) {
        samples.append(s)

        // Trim to historySize while keeping pending candidate alive (or refuse if impossible).
        if samples.count > cfg.historySize {
            let removeCount = samples.count - cfg.historySize
            samples.removeFirst(removeCount)

            if let p = pending {
                let newPeak = p.peakIndex - removeCount
                if newPeak < 0 {
                    log("[IMPACT] candidate refused reason=history_truncated")
                    pending = nil
                } else {
                    pending = PendingCandidate(
                        peakIndex: newPeak,
                        triggers: p.triggers,
                        percentile: p.percentile,
                        score: p.score
                    )
                }
            }
        }
    }

    // MARK: - RS + Geometry Helpers

    private func maxAbs(in range: ArraySlice<Sample>, key: (Sample) -> Double?) -> Double? {
        var best: Double? = nil
        for s in range {
            guard let v = key(s), v.isFinite else { continue }
            if let b = best {
                if v > b { best = v }
            } else {
                best = v
            }
        }
        return best
    }

    private func directionConsistencyDeg(pre: Sample, mid: Sample, post: Sample) -> Double? {
        guard
            let p = pre.centroidPx, let m = mid.centroidPx, let q = post.centroidPx
        else { return nil }

        let v1 = m - p
        let v2 = q - m

        let n1 = simd_length(v1)
        let n2 = simd_length(v2)
        guard n1 > 1e-6, n2 > 1e-6 else { return nil }

        let dot = simd_dot(v1 / n1, v2 / n2)
        let clamped = min(1.0, max(-1.0, dot))
        let ang = acos(clamped) * 180.0 / .pi
        return ang.isFinite ? ang : nil
    }

    // MARK: - Robust Stats

    private func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let ys = xs.sorted()
        let n = ys.count
        if n % 2 == 1 {
            return ys[n / 2]
        } else {
            return 0.5 * (ys[n / 2 - 1] + ys[n / 2])
        }
    }

    private func mad(_ xs: [Double], _ med: Double) -> Double {
        guard !xs.isEmpty else { return 0.0 }
        let devs = xs.map { abs($0 - med) }
        return median(devs) ?? 0.0
    }

    private func percentile(of x: Double, comparedTo baseline: [Double]) -> Double {
        guard !baseline.isEmpty else { return 0.0 }
        let countLess = baseline.reduce(0) { $0 + (($1 < x) ? 1 : 0) }
        return Double(countLess) / Double(baseline.count)
    }

    private func safeDt(prevNow: Double?, now: Double) -> Double? {
        guard let p = prevNow else { return nil }
        let dt = now - p
        guard dt.isFinite, dt > 1e-6 else { return nil }
        return dt
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        if DebugProbe.isEnabled(.capture) {
            print(msg)
        }
    }

    private func fmt(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "n/a" }
        return String(format: "%.3f", v)
    }

    private func fmt(_ v: Float?) -> String {
        guard let v, v.isFinite else { return "n/a" }
        return String(format: "%.2f", v)
    }

    private func fmtInt(_ v: Int?) -> String {
        guard let v else { return "n/a" }
        return "\(v)"
    }

    private func fmtPct(_ v: Double) -> String {
        guard v.isFinite else { return "n/a" }
        return String(format: "%.3f", v)
    }

    private func fmtProfile(_ arr: [Double]?) -> String {
        guard let arr, !arr.isEmpty else { return "n/a" }
        let n = arr.count
        let k = min(n, cfg.maxScanlineProfilePrintCount)
        let head = arr.prefix(k).map { String(format: "%.2f", $0) }.joined(separator: ",")
        if n > k {
            return "[\(head), ...] n=\(n)"
        } else {
            return "[\(head)]"
        }
    }

    private func fmtTriggers(_ triggers: [MetricScore]) -> String {
        // Keep the list readable and deterministic.
        let top = triggers.prefix(4)
        let s = top
            .map { "\($0.metric.rawValue)(z=\(String(format: "%.2f", $0.z)))" }
            .joined(separator: ",")
        return "[\(s)]"
    }

    private func fmtBoolTriplet(_ a: Bool?, _ b: Bool?, _ c: Bool?) -> String {
        func f(_ x: Bool?) -> String {
            guard let x else { return "n/a" }
            return x ? "1" : "0"
        }
        return "\(f(a))/\(f(b))/\(f(c))"
    }
}
