//
//  SceneQuietGate.swift
//  LaunchLab
//
//  Scene Quiet Authority (V1)
//
//  Purpose:
//  - Declare when the scene is "quiet" enough to re-arm shot authority.
//  - Quiet is NOT "ball absent"; it is "no coherent, strike-like motion."
//
//  Constraints:
//  - Engine-only
//  - No UI
//  - No smoothing/averaging of signals
//  - No per-frame spam: logs only on transitions
//

import Foundation
import CoreGraphics

// MARK: - Config

struct SceneQuietGateConfig: Equatable {

    /// Number of consecutive "quiet candidate" frames required to enter QUIET.
    let minQuietFramesToEnter: Int

    /// If instantaneous speed is below this, treat as quiet candidate (even if locked).
    let quietMotionPxPerSec: Double

    /// If instantaneous speed exceeds this, treat as NOT quiet (regardless of coherence).
    let definitelyNotQuietPxPerSec: Double

    /// Number of recent velocity vectors to retain for coherence evaluation.
    let coherenceWindow: Int

    /// Minimum speed required to consider a velocity vector for coherence.
    let minSpeedForCoherencePxPerSec: Double

    /// If coherence ratio (direction consistency) is >= this, treat motion as coherent -> NOT quiet.
    /// If coherence ratio is < this, treat motion as incoherent jitter -> quiet candidate (when speed is moderate).
    let minCoherenceRatioForNotQuiet: Double

    init(
        minQuietFramesToEnter: Int = 12,
        quietMotionPxPerSec: Double = 20.0,
        definitelyNotQuietPxPerSec: Double = 250.0,
        coherenceWindow: Int = 8,
        minSpeedForCoherencePxPerSec: Double = 15.0,
        minCoherenceRatioForNotQuiet: Double = 0.60
    ) {
        self.minQuietFramesToEnter = max(1, minQuietFramesToEnter)
        self.quietMotionPxPerSec = max(0, quietMotionPxPerSec)
        self.definitelyNotQuietPxPerSec = max(self.quietMotionPxPerSec, definitelyNotQuietPxPerSec)
        self.coherenceWindow = max(2, coherenceWindow)
        self.minSpeedForCoherencePxPerSec = max(0, minSpeedForCoherencePxPerSec)
        self.minCoherenceRatioForNotQuiet = min(1.0, max(0.0, minCoherenceRatioForNotQuiet))
    }
}

// MARK: - Input/Output

struct SceneQuietGateInput: Equatable {
    let timestampSec: Double
    let ballLocked: Bool
    let ballLockConfidence: Float
    let instantaneousPxPerSec: Double
    /// Velocity in pixels per tick (dx, dy) for direction coherence. Optional.
    let velocityPx: CGVector?
}

struct SceneQuietGateOutput: Equatable {
    /// True when the gate is in a QUIET state (after minQuietFramesToEnter).
    let isQuiet: Bool
    /// Consecutive quiet-candidate frames (resets to 0 when not quiet-candidate).
    let quietCandidateFrames: Int
}

// MARK: - Gate

final class SceneQuietGate {

    private enum State: Equatable {
        case notQuiet
        case quiet
    }

    private let config: SceneQuietGateConfig

    private var state: State = .notQuiet
    private var quietCandidateFrames: Int = 0

    // Recent normalized velocity directions used for coherence checking.
    private var recentDirs: [CGVector] = []

    init(config: SceneQuietGateConfig = SceneQuietGateConfig()) {
        self.config = config
    }

    func reset() {
        state = .notQuiet
        quietCandidateFrames = 0
        recentDirs.removeAll()
    }

    func update(_ input: SceneQuietGateInput) -> SceneQuietGateOutput {

        // Update coherence buffer (only when we have usable velocity + speed).
        if let v = input.velocityPx, input.instantaneousPxPerSec >= config.minSpeedForCoherencePxPerSec {
            if let n = normalize(v) {
                recentDirs.append(n)
                if recentDirs.count > config.coherenceWindow {
                    recentDirs.removeFirst(recentDirs.count - config.coherenceWindow)
                }
            }
        }

        let coherenceRatio = computeCoherenceRatio(from: recentDirs)

        // Decide if this frame is a "quiet candidate"
        let isQuietCandidate: Bool = {
            // If nothing is locked, we treat as quiet candidate.
            if !input.ballLocked { return true }

            // Locked, but essentially no motion.
            if input.instantaneousPxPerSec <= config.quietMotionPxPerSec { return true }

            // Locked, very high motion -> never quiet.
            if input.instantaneousPxPerSec >= config.definitelyNotQuietPxPerSec { return false }

            // Locked, moderate motion: use coherence.
            // If coherence is unknown (insufficient samples), be conservative (NOT quiet).
            guard let coherenceRatio else { return false }

            // Coherent motion => NOT quiet. Incoherent => quiet candidate.
            return coherenceRatio < config.minCoherenceRatioForNotQuiet
        }()

        if isQuietCandidate {
            quietCandidateFrames += 1
        } else {
            quietCandidateFrames = 0
        }

        // State transitions (log ONCE).
        switch state {

        case .notQuiet:
            if quietCandidateFrames >= config.minQuietFramesToEnter {
                state = .quiet
                logQuietEntered(input: input, coherenceRatio: coherenceRatio)
            }

        case .quiet:
            if !isQuietCandidate {
                state = .notQuiet
                logQuietExited(input: input, coherenceRatio: coherenceRatio)
            }
        }

        return SceneQuietGateOutput(
            isQuiet: state == .quiet,
            quietCandidateFrames: quietCandidateFrames
        )
    }

    // MARK: - Logging (transition-only)

    private func logQuietEntered(input: SceneQuietGateInput, coherenceRatio: Double?) {
        let t = fmt(input.timestampSec)
        let conf = fmt(input.ballLockConfidence)
        let pxs = fmt(input.instantaneousPxPerSec)
        let coh = fmt(coherenceRatio)

        let msg =
            "quiet_entered " +
            "t=\(t) " +
            "frames=\(quietCandidateFrames) " +
            "locked=\(input.ballLocked) " +
            "conf=\(conf) " +
            "px_s=\(pxs) " +
            "coh=\(coh) " +
            "quiet_thr=\(fmt(config.quietMotionPxPerSec)) " +
            "hard_thr=\(fmt(config.definitelyNotQuietPxPerSec))"

        Log.info(.authority, msg)
    }

    private func logQuietExited(input: SceneQuietGateInput, coherenceRatio: Double?) {
        let t = fmt(input.timestampSec)
        let conf = fmt(input.ballLockConfidence)
        let pxs = fmt(input.instantaneousPxPerSec)
        let coh = fmt(coherenceRatio)

        let reason: String = {
            if input.instantaneousPxPerSec >= config.definitelyNotQuietPxPerSec { return "motion_fast" }
            if let coherenceRatio, coherenceRatio >= config.minCoherenceRatioForNotQuiet { return "motion_coherent" }
            return "motion_or_unknown"
        }()

        let msg =
            "quiet_exited " +
            "t=\(t) " +
            "reason=\(reason) " +
            "locked=\(input.ballLocked) " +
            "conf=\(conf) " +
            "px_s=\(pxs) " +
            "coh=\(coh)"

        Log.info(.authority, msg)
    }

    // MARK: - Math

    private func normalize(_ v: CGVector) -> CGVector? {
        let mag = sqrt(v.dx * v.dx + v.dy * v.dy)
        guard mag > 1e-6 else { return nil }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }

    /// Returns coherence ratio in [0,1], or nil if insufficient samples.
    /// Coherence ratio = fraction of consecutive direction pairs with positive dot product.
    private func computeCoherenceRatio(from dirs: [CGVector]) -> Double? {
        guard dirs.count >= 2 else { return nil }

        var total = 0
        var coherent = 0

        for i in 1..<dirs.count {
            let a = dirs[i - 1]
            let b = dirs[i]
            let dot = (a.dx * b.dx) + (a.dy * b.dy)
            total += 1
            if dot > 0 { coherent += 1 }
        }

        guard total > 0 else { return nil }
        return Double(coherent) / Double(total)
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Double?) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.3f", v)
    }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
