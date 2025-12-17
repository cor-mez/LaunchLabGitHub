import Foundation
import simd

// MARK: - Config

public struct RSPnPPoseStabilityConfig: Equatable {
    public let historySize: Int
    public let minSamplesForCorrelation: Int
    public let logEveryNSuccesses: Int

    public init(
        historySize: Int = 20,
        minSamplesForCorrelation: Int = 8,
        logEveryNSuccesses: Int = 1
    ) {
        self.historySize = max(5, historySize)
        self.minSamplesForCorrelation = max(5, minSamplesForCorrelation)
        self.logEveryNSuccesses = max(1, logEveryNSuccesses)
    }
}

// Convenience
private extension SIMD4 where Scalar == Double {
    var xyz: SIMD3<Double> {
        SIMD3<Double>(x, y, z)
    }
}

public final class RSPnPPoseStabilityCharacterizer {

    // MARK: - Context

    public struct SampleContext {
        let confidence: Float
        let frameCount: Int
        let spanSec: Double
        let stalenessSec: Double
        let motionPx: Double?
    }

    // MARK: - State

    private let cfg: RSPnPPoseStabilityConfig

    // Pose-run scoped state
    private var anchorPose: simd_double4x4?
    private var lastPose: simd_double4x4?
    private var runSampleCount: Int = 0

    // MARK: - Init

    public init(config: RSPnPPoseStabilityConfig) {
        self.cfg = config
    }

    // MARK: - Observations

    /// Called when pose is refused, skipped, or failed
    public func observeNoPose(nowSec: Double, reason: String) {

        if runSampleCount > 0 {
            if DebugProbe.isEnabled(.capture) {
                print("[POSE] lifetime_frames=\(runSampleCount)")
            }
        }

        anchorPose = nil
        lastPose = nil
        runSampleCount = 0

        if DebugProbe.isEnabled(.capture) {
            print("[POSE] none reason=\(reason)")
        }
    }

    /// Called only on successful pose emission
    public func observeSuccess(
        nowSec: Double,
        pose: simd_double4x4,
        context: SampleContext
    ) {

        // Start of a new pose run
        if anchorPose == nil {
            anchorPose = pose
            lastPose = nil
            runSampleCount = 0

            if DebugProbe.isEnabled(.capture) {
                print("[POSE] run_start conf=\(fmt(context.confidence)) span=\(fmt(context.spanSec))")
            }
        }

        runSampleCount += 1

        // Log sampling cadence
        guard runSampleCount % cfg.logEveryNSuccesses == 0 else {
            lastPose = pose
            return
        }

        if let prev = lastPose {
            let dT = translationDelta(from: prev, to: pose)
            let dR = rotationDeltaDeg(from: prev, to: pose)

            print("[POSE] delta_t=\(fmt(dT)) delta_r=\(fmt(dR))")
        }

        if let anchor = anchorPose {
            let driftT = translationDelta(from: anchor, to: pose)
            let driftR = rotationDeltaDeg(from: anchor, to: pose)

            print("[POSE] drift_t=\(fmt(driftT)) drift_r=\(fmt(driftR))")
            print(
                "[POSE] correlate conf=\(fmt(context.confidence)) " +
                "span=\(fmt(context.spanSec)) " +
                "motion=\(fmt(context.motionPx))"
            )
        }

        lastPose = pose
    }

    // MARK: - Math

    private func translationDelta(from a: simd_double4x4, to b: simd_double4x4) -> Double {
        let ta = SIMD3<Double>(a.columns.3.x, a.columns.3.y, a.columns.3.z)
        let tb = SIMD3<Double>(b.columns.3.x, b.columns.3.y, b.columns.3.z)
        return simd_length(tb - ta)
    }

    private func rotationDeltaDeg(from a: simd_double4x4, to b: simd_double4x4) -> Double {
        let ra = simd_double3x3(
            a.columns.0.xyz,
            a.columns.1.xyz,
            a.columns.2.xyz
        )

        let rb = simd_double3x3(
            b.columns.0.xyz,
            b.columns.1.xyz,
            b.columns.2.xyz
        )

        let qa = simd_quatd(ra)
        let qb = simd_quatd(rb)

        let dot = abs(simd_dot(qa.vector, qb.vector))
        let angle = 2.0 * acos(min(1.0, dot))
        return angle * 180.0 / .pi
    }

    // MARK: - Formatting

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.3f", v)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }

    private func fmt(_ v: Float) -> String {
        String(format: "%.2f", v)
    }
}
