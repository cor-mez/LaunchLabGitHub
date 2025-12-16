//
//  RSPnPPoseStabilityCharacterizer.swift
//  Engine
//
//  Pose Consumption & Stability Characterization (observational only)
//  - No smoothing / filtering
//  - No interpolation
//  - No retries
//  - No downstream emission
//

import Foundation
import simd

// MARK: - Config

public struct RSPnPPoseStabilityConfig: Equatable {
    public var historySize: Int
    public var minSamplesForCorrelation: Int
    public var logEveryNSuccesses: Int

    public init(historySize: Int = 20,
                minSamplesForCorrelation: Int = 8,
                logEveryNSuccesses: Int = 1) {
        self.historySize = max(5, historySize)
        self.minSamplesForCorrelation = max(5, minSamplesForCorrelation)
        self.logEveryNSuccesses = max(1, logEveryNSuccesses)
    }
}

// MARK: - Pose Contract (read-only)

public protocol RSPnPPoseTelemetryProviding {
    var rspnp_poseMatrix: simd_double4x4 { get }
}

extension simd_double4x4: RSPnPPoseTelemetryProviding {
    public var rspnp_poseMatrix: simd_double4x4 { self }
}

extension simd_float4x4: RSPnPPoseTelemetryProviding {
    public var rspnp_poseMatrix: simd_double4x4 {
        simd_double4x4(
            SIMD4<Double>(self.columns.0),
            SIMD4<Double>(self.columns.1),
            SIMD4<Double>(self.columns.2),
            SIMD4<Double>(self.columns.3)
        )
    }
}

// MARK: - Characterizer

public final class RSPnPPoseStabilityCharacterizer {

    // MARK: - Context

    public struct SampleContext: Equatable {
        public var confidence: Float
        public var frameCount: Int
        public var spanSec: Double
        public var stalenessSec: Double
        public var motionPx: Double?

        public init(confidence: Float,
                    frameCount: Int,
                    spanSec: Double,
                    stalenessSec: Double,
                    motionPx: Double?) {
            self.confidence = confidence
            self.frameCount = frameCount
            self.spanSec = spanSec
            self.stalenessSec = stalenessSec
            self.motionPx = motionPx
        }
    }

    // MARK: - Internal Types

    private struct PoseCanonical {
        let t: SIMD3<Double>
        let q: simd_quatd
    }

    private struct PoseDelta {
        let dTransM: Double
        let dRotDeg: Double
    }

    // MARK: - State

    private let cfg: RSPnPPoseStabilityConfig
    private var successCount = 0

    private var lastPose: PoseCanonical?
    private var anchorPose: PoseCanonical?
    private var anchorTimeSec: Double?

    private var recentDeltas: RingBuffer<PoseDelta>

    private var corrConf_dTrans = OnlineCorrelation()
    private var corrConf_dRot   = OnlineCorrelation()
    private var corrMotion_dTrans = OnlineCorrelation()
    private var corrMotion_dRot   = OnlineCorrelation()

    // MARK: - Init

    public init(config: RSPnPPoseStabilityConfig = RSPnPPoseStabilityConfig()) {
        self.cfg = config
        self.recentDeltas = RingBuffer(capacity: config.historySize)
    }

    // MARK: - Observation API

    public func observeNoPose(nowSec: Double, reason: String) {
        anchorPose = nil
        anchorTimeSec = nil
        lastPose = nil

        if DebugProbe.isEnabled(.capture) {
            print("[RSPNP][POSE] none — \(reason)")
        }
    }

    public func observeSuccess(
        nowSec: Double,
        pose: RSPnPPoseTelemetryProviding,
        context: SampleContext
    ) {
        successCount += 1
        guard (successCount % cfg.logEveryNSuccesses) == 0 else { return }

        let canon = canonicalize(pose.rspnp_poseMatrix)

        if anchorPose == nil {
            anchorPose = canon
            anchorTimeSec = nowSec
        }

        let deltaPrev = lastPose.map { poseDelta(from: $0, to: canon) }
        if let dp = deltaPrev { recentDeltas.push(dp) }

        let deltaAnchor = anchorPose.map { poseDelta(from: $0, to: canon) }
        let ageSec = anchorTimeSec.map { max(0, nowSec - $0) } ?? 0

        if let dp = deltaPrev {
            corrConf_dTrans.add(x: Double(context.confidence), y: dp.dTransM)
            corrConf_dRot.add(x: Double(context.confidence), y: dp.dRotDeg)

            if let m = context.motionPx {
                corrMotion_dTrans.add(x: m, y: dp.dTransM)
                corrMotion_dRot.add(x: m, y: dp.dRotDeg)
            }
        }

        let (stdT, stdR) = recentStdDev()

        if DebugProbe.isEnabled(.capture) {
            let dT = deltaPrev?.dTransM ?? 0
            let dR = deltaPrev?.dRotDeg ?? 0
            let driftT = deltaAnchor?.dTransM ?? 0
            let driftR = deltaAnchor?.dRotDeg ?? 0

            let rConfT = corrConf_dTrans.correlation(minN: cfg.minSamplesForCorrelation)
            let rConfR = corrConf_dRot.correlation(minN: cfg.minSamplesForCorrelation)
            let rMotT  = corrMotion_dTrans.correlation(minN: cfg.minSamplesForCorrelation)
            let rMotR  = corrMotion_dRot.correlation(minN: cfg.minSamplesForCorrelation)

            print("""
[RSPNP][POSE] ok
  dT=\(fmt(dT))m dR=\(fmt(dR))deg
  stdT=\(fmt(stdT))m stdR=\(fmt(stdR))deg
  driftT=\(fmt(driftT))m driftR=\(fmt(driftR))deg age=\(fmt(ageSec))s
  conf=\(fmt(context.confidence)) motionPx=\(fmtOpt(context.motionPx))
  win(frames=\(context.frameCount) span=\(fmt(context.spanSec))s stale=\(fmt(context.stalenessSec))s)
  corr(conf,dT)=\(fmtOpt(rConfT)) corr(conf,dR)=\(fmtOpt(rConfR))
  corr(motion,dT)=\(fmtOpt(rMotT)) corr(motion,dR)=\(fmtOpt(rMotR))
""")
        }

        lastPose = canon
    }

    // MARK: - Math

    private func canonicalize(_ m: simd_double4x4) -> PoseCanonical {
        let t = SIMD3<Double>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let r3 = simd_double3x3(
            SIMD3<Double>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Double>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Double>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
        let q = simd_quatd(r3).normalized
        return PoseCanonical(t: t, q: q)
    }

    private func poseDelta(from a: PoseCanonical, to b: PoseCanonical) -> PoseDelta {
        let dt = simd_length(b.t - a.t)
        let dot = abs(simd_dot(a.q.vector, b.q.vector))
        let clamped = max(-1.0, min(1.0, dot))
        let angleRad = 2.0 * acos(clamped)
        let angleDeg = angleRad * 180.0 / Double.pi
        return PoseDelta(dTransM: dt, dRotDeg: angleDeg)
    }

    private func recentStdDev() -> (Double, Double) {
        let ds = recentDeltas.values
        guard ds.count >= 2 else { return (0, 0) }

        func std(_ xs: [Double]) -> Double {
            let mean = xs.reduce(0, +) / Double(xs.count)
            let varSum = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            return sqrt(max(0, varSum / Double(xs.count - 1)))
        }

        return (std(ds.map { $0.dTransM }),
                std(ds.map { $0.dRotDeg }))
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.4f", v) }
    private func fmt(_ v: Float)  -> String { String(format: "%.2f", v) }
    private func fmtOpt(_ v: Double?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.3f", v)
    }
}

// MARK: - Utilities

private struct RingBuffer<T> {
    private(set) var values: [T] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        values.reserveCapacity(self.capacity)
    }

    mutating func push(_ v: T) {
        values.append(v)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}

private struct OnlineCorrelation {
    private var n = 0
    private var meanX = 0.0
    private var meanY = 0.0
    private var c = 0.0
    private var sx = 0.0
    private var sy = 0.0

    mutating func add(x: Double, y: Double) {
        n += 1
        let dx = x - meanX
        meanX += dx / Double(n)
        let dy = y - meanY
        meanY += dy / Double(n)
        c  += dx * (y - meanY)
        sx += dx * (x - meanX)
        sy += dy * (y - meanY)
    }

    func correlation(minN: Int) -> Double? {
        guard n >= minN else { return nil }
        let denom = sqrt(max(0, sx) * max(0, sy))
        return denom > 0 ? c / denom : nil
    }
}
