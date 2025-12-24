//
//  ImpactCenteredDynamicObservabilityModule.swift
//  LaunchLab
//
//  Impact-Centered Dynamic Observability (ICDO)
//  LOG-ONLY — no pose, no spin, no downstream effects
//

import Foundation
import simd

// MARK: - Config

public struct ImpactCenteredDynamicObservabilityConfig: Equatable {
    public var enabled: Bool
    public var historySize: Int
    public var preFrames: Int
    public var postFrames: Int

    public init(
        enabled: Bool = true,
        historySize: Int = 180,
        preFrames: Int = 3,
        postFrames: Int = 3
    ) {
        self.enabled = enabled
        self.historySize = max(16, historySize)
        self.preFrames = max(1, preFrames)
        self.postFrames = max(1, postFrames)
    }
}

// MARK: - Observation Input

 struct ICDOObservation {
    public let timestampSec: Double
    public let frameIndex: Int?
    public let centroidPx: SIMD2<Double>?
    public let ballRadiusPx: Double?
    public let compactness: Double?
    public let densityCount: Int?
    public let fast9Points: [SIMD2<Double>]?
    public let scanlineMotionProfile: [Double]?
    public let ballLockConfidence: Float?
    public let mdgAccepted: Bool?
    public let rsWindowValid: Bool?
    public let rowTiming: RSRowTiming?

     init(
        timestampSec: Double,
        frameIndex: Int? = nil,
        centroidPx: SIMD2<Double>? = nil,
        ballRadiusPx: Double? = nil,
        compactness: Double? = nil,
        densityCount: Int? = nil,
        fast9Points: [SIMD2<Double>]? = nil,
        scanlineMotionProfile: [Double]? = nil,
        ballLockConfidence: Float? = nil,
        mdgAccepted: Bool? = nil,
        rsWindowValid: Bool? = nil,
        rowTiming: RSRowTiming? = nil
    ) {
        self.timestampSec = timestampSec
        self.frameIndex = frameIndex
        self.centroidPx = centroidPx
        self.ballRadiusPx = ballRadiusPx
        self.compactness = compactness
        self.densityCount = densityCount
        self.fast9Points = fast9Points
        self.scanlineMotionProfile = scanlineMotionProfile
        self.ballLockConfidence = ballLockConfidence
        self.mdgAccepted = mdgAccepted
        self.rsWindowValid = rsWindowValid
        self.rowTiming = rowTiming
    }
}

// MARK: - Module

public final class ImpactCenteredDynamicObservabilityModule {

    private struct Sample {
        let timestampSec: Double
        let frameIndex: Int
        let centroidPx: SIMD2<Double>?

        let centroidVelocity: SIMD2<Double>?
        let centroidAcceleration: SIMD2<Double>?
        let centroidAccelMag: Double?

        let fast9Dispersion: Double?
        let densityDelta: Double?

        let compactness: Double?
        let radiusPx: Double?

        let scanlineVariance: Double?
        let rsShear: Double?
        let rsTemporalAsymmetry: Double?

        let ballLockConfidence: Float?
        let mdgAccepted: Bool?
        let rsWindowValid: Bool?

        let signalEnergy: Double?
    }

    private struct Candidate {
        let peakIndex: Int
    }

    private let config: ImpactCenteredDynamicObservabilityConfig
    private var samples: [Sample] = []
    private var pending: Candidate?
    private var autoFrame: Int = 0

    public init(config: ImpactCenteredDynamicObservabilityConfig = .init()) {
        self.config = config
    }

    // MARK: - Public API

     func observe(_ obs: ICDOObservation) {
        guard config.enabled else { return }

        let frame = obs.frameIndex ?? autoFrame
        if obs.frameIndex == nil { autoFrame += 1 }

        let prev = samples.last
        let dt = prev.flatMap { deltaTime(from: $0.timestampSec, to: obs.timestampSec) }

        let velocity = vectorDelta(prev?.centroidPx, obs.centroidPx, dt)
        let acceleration = vectorDelta(prev?.centroidVelocity, velocity, dt)
        let accelMag = acceleration.map { simd_length($0) }

        let densityDelta = delta(prev?.densityDelta, obs.densityCount.map(Double.init))
        let fast9Dispersion = variance(displacements(prev?.fast9Dispersion, obs.fast9Points))

        let rsStats = rsStats(from: obs.scanlineMotionProfile)

        let signalEnergy = [
            accelMag,
            fast9Dispersion,
            densityDelta,
            rsStats.shear,
            rsStats.asymmetry,
            rsStats.variance
        ].compactMap { $0 }.reduce(0, +)

        let sample = Sample(
            timestampSec: obs.timestampSec,
            frameIndex: frame,
            centroidPx: obs.centroidPx,
            centroidVelocity: velocity,
            centroidAcceleration: acceleration,
            centroidAccelMag: accelMag,
            fast9Dispersion: fast9Dispersion,
            densityDelta: densityDelta,
            compactness: obs.compactness,
            radiusPx: obs.ballRadiusPx,
            scanlineVariance: rsStats.variance,
            rsShear: rsStats.shear,
            rsTemporalAsymmetry: rsStats.asymmetry,
            ballLockConfidence: obs.ballLockConfidence,
            mdgAccepted: obs.mdgAccepted,
            rsWindowValid: obs.rsWindowValid,
            signalEnergy: signalEnergy
        )

        append(sample)
        detectCandidateIfNeeded()
        finalizeCandidateIfReady()
    }

    // MARK: - Candidate Logic

    private func detectCandidateIfNeeded() {
        guard pending == nil, samples.count >= 3 else { return }

        let i = samples.count - 2
        guard
            let a = samples[i - 1].signalEnergy,
            let b = samples[i].signalEnergy,
            let c = samples[i + 1].signalEnergy,
            b > a, b > c
        else { return }

        pending = Candidate(peakIndex: i)
    }

    private func finalizeCandidateIfReady() {
        guard let cand = pending else { return }
        let end = cand.peakIndex + config.postFrames
        guard end < samples.count else { return }

        let start = max(0, cand.peakIndex - config.preFrames)
        let pre = samples[start]
        let peak = samples[cand.peakIndex]
        let post = samples[end]

        let spanMs = (post.timestampSec - pre.timestampSec) * 1000.0

        log("[IMPACT] candidate start frame=\(pre.frameIndex)")
        log("[IMPACT] candidate span_ms=\(fmt(spanMs))")
        log("[IMPACT] signals=\(formatSignals(for: peak))")

        log("[IMPACT][GEOM] pre compactness=\(fmt(pre.compactness)) during=\(fmt(peak.compactness)) post=\(fmt(post.compactness))")
        log("[IMPACT][CONF] pre=\(fmt(pre.ballLockConfidence)) during=\(fmt(peak.ballLockConfidence)) post=\(fmt(post.ballLockConfidence))")

        pending = nil
    }

    // MARK: - Utilities

    private func append(_ s: Sample) {
        samples.append(s)
        if samples.count > config.historySize {
            samples.removeFirst(samples.count - config.historySize)
        }
    }

    private func deltaTime(from a: Double, to b: Double) -> Double? {
        let dt = b - a
        return dt > 0 ? dt : nil
    }

    private func vectorDelta(_ a: SIMD2<Double>?, _ b: SIMD2<Double>?, _ dt: Double?) -> SIMD2<Double>? {
        guard let a, let b, let dt, dt > 0 else { return nil }
        return (b - a) / dt
    }

    private func delta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return b - a
    }

    private func rsStats(from profile: [Double]?) -> (variance: Double?, shear: Double?, asymmetry: Double?) {
        guard let profile, !profile.isEmpty else { return (nil, nil, nil) }
        let mid = profile.count / 2
        let top = Array(profile.prefix(mid))
        let bottom = Array(profile.suffix(profile.count - mid))
        let topMean = mean(top)
        let bottomMean = mean(bottom)
        return (
            variance(profile),
            bottomMean.flatMap { b in topMean.map { b - $0 } },
            topMean.flatMap { t in bottomMean.map { t - $0 } }
        )
    }

    private func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private func variance(_ xs: [Double]?) -> Double? {
        guard let xs, let m = mean(xs) else { return nil }
        return xs.reduce(0) { $0 + pow($1 - m, 2) } / Double(xs.count)
    }

    private func displacements(_ prev: Double?, _ pts: [SIMD2<Double>]?) -> [Double] {
        guard let pts else { return [] }
        return pts.map { simd_length($0) }
    }

    private func formatSignals(for s: Sample) -> String {
        var parts: [String] = []
        if s.centroidAccelMag != nil { parts.append("accel") }
        if s.fast9Dispersion != nil { parts.append("fast9") }
        if s.densityDelta != nil { parts.append("density") }
        if s.rsShear != nil { parts.append("shear") }
        if s.rsTemporalAsymmetry != nil { parts.append("asym") }
        if s.scanlineVariance != nil { parts.append("scanline") }
        return "[\(parts.joined(separator: ","))]"
    }

    private func log(_ msg: String) {
        guard DebugProbe.isEnabled(.capture) else { return }
        Log.info(.detection, msg)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "n/a" }
        return String(format: "%.3f", v)
    }

    private func fmt(_ v: Float?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.2f", v)
    }
}
