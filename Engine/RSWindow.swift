import Foundation
import CoreGraphics

// MARK: - RSWindow
// Rolling-shutter observation window (confidence-gated, read-only consumer).

/// Optional rolling-shutter timing metadata for a frame.
/// Keep it minimal in V1; populate later if/when the camera pipeline exposes it.
struct RSRowTiming: Equatable {
    /// Sensor/image height in pixels (rows). Used to interpret rolling shutter timing.
    let imageHeightPx: Int

    /// Total sensor readout time from first to last row (seconds), if known.
    /// If you only know per-row time, store readoutTimeSec = rowTimeSec * (imageHeightPx - 1).
    let readoutTimeSec: Double?

    /// Exposure duration (seconds), if known.
    let exposureTimeSec: Double?

    init(imageHeightPx: Int, readoutTimeSec: Double? = nil, exposureTimeSec: Double? = nil) {
        self.imageHeightPx = max(0, imageHeightPx)
        self.readoutTimeSec = readoutTimeSec
        self.exposureTimeSec = exposureTimeSec
    }
}

/// A single frame observation (BallLock output + time metadata).
struct RSWindowFrame: Equatable {
    let ballCenter2D: CGPoint
    let ballRadiusPx: CGFloat
    let timestampSec: Double
    let confidence: Float
    let rowTiming: RSRowTiming?
}

/// Configuration for RSWindow.
struct RSWindowConfig: Equatable {
    /// Rolling buffer capacity (default 5).
    var capacity: Int = 5

    /// Minimum frames required to be considered "ready" for a solver (default 3).
    var minFrames: Int = 3

    /// Hard gate: ONLY accept frames when confidence >= threshold.
    var confidenceThreshold: Float = 12.0

    /// Maximum time since the most recently accepted frame (seconds) for the window to remain valid.
    /// If staleness exceeds this, the window is cleared.
    var maxStalenessSec: Double = 0.25

    /// Maximum temporal span between first and last frames (seconds).
    /// If span exceeds this, the window is cleared (we want a short RS window).
    var maxSpanSec: Double = 0.25

    init(
        capacity: Int = 5,
        minFrames: Int = 3,
        confidenceThreshold: Float = 12.0,
        maxStalenessSec: Double = 0.25,
        maxSpanSec: Double = 0.25
    ) {
        self.capacity = max(1, capacity)
        self.minFrames = max(1, minFrames)
        self.confidenceThreshold = confidenceThreshold
        self.maxStalenessSec = max(0, maxStalenessSec)
        self.maxSpanSec = max(0, maxSpanSec)
    }
}

/// Immutable snapshot passed into solvers (prevents mutation).
struct RSWindowSnapshot: Equatable {
    let frames: [RSWindowFrame]
    let snapshotTimeSec: Double
    let config: RSWindowConfig

    var frameCount: Int { frames.count }

    /// Duration covered by the window content (last - first).
    var spanSec: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return max(0, last.timestampSec - first.timestampSec)
    }

    /// Time since the last accepted frame (snapshotTime - lastTimestamp).
    var stalenessSec: Double {
        guard let last = frames.last else { return .infinity }
        return max(0, snapshotTimeSec - last.timestampSec)
    }

    var confidenceMin: Float {
        frames.map(\.confidence).min() ?? 0
    }

    var confidenceMax: Float {
        frames.map(\.confidence).max() ?? 0
    }

    var confidenceAvg: Float {
        guard !frames.isEmpty else { return 0 }
        let s = frames.reduce(Float(0)) { $0 + $1.confidence }
        return s / Float(frames.count)
    }

    /// Window validity is purely structural/time-based.
    /// Confidence gating happens on ingest (frames are only admitted when confident),
    /// but we still validate age/span/count here for solver safety.
    var isValid: Bool {
        guard frameCount >= config.minFrames else { return false }
        guard stalenessSec <= config.maxStalenessSec else { return false }
        guard spanSec <= config.maxSpanSec else { return false }
        return true
    }
}

/// Ingest decision used to avoid calling the solver every frame (no per-frame spam).
enum RSWindowIngestDecision: Equatable {
    case accepted(frameCount: Int)
    case rejectedLowConfidence(confidence: Float, threshold: Float)
    case cleared(reason: String)
}

/// Rolling buffer of high-confidence BallLock observations.
final class RSWindow {

    private let config: RSWindowConfig
    private var frames: [RSWindowFrame] = []
    private var lastTickSec: Double = 0

    // Logging state (to avoid per-frame spam).
    private enum LogState: Equatable {
        case idle
        case collecting
        case ready
        case rejectingLowConfidence
    }
    private var logState: LogState = .idle
    private var lastLoggedClearReason: String? = nil

    init(config: RSWindowConfig = RSWindowConfig()) {
        self.config = config
    }

    // Exposed (read-only) surface.
    var frameCount: Int { frames.count }

    /// Window age (span across frames).
    var windowAgeSec: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return max(0, last.timestampSec - first.timestampSec)
    }

    /// Current staleness based on last tick.
    var stalenessSec: Double {
        guard let last = frames.last else { return .infinity }
        return max(0, lastTickSec - last.timestampSec)
    }

    /// Validity at the *current* tick.
    var isValid: Bool {
        guard frames.count >= config.minFrames else { return false }
        guard stalenessSec <= config.maxStalenessSec else { return false }
        guard windowAgeSec <= config.maxSpanSec else { return false }
        return true
    }

    /// Ingest one BallLock observation (read-only), strictly gated by confidence.
    /// - Important: This never interpolates, never recovers, and never feeds back upstream.
    @discardableResult
    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        confidence: Float,
        rowTiming: RSRowTiming? = nil
    ) -> RSWindowIngestDecision {

        lastTickSec = timestampSec

        // If we have an existing window and it has gone stale, clear it.
        if clearIfStale(nowSec: timestampSec) {
            // clearIfStale logs (transition-based)
            // Continue and evaluate this frame normally.
        }

        // Gate: confidence is law.
        guard confidence >= config.confidenceThreshold else {
            transitionToRejecting(confidence: confidence)
            return .rejectedLowConfidence(confidence: confidence, threshold: config.confidenceThreshold)
        }

        // If timestamps go backwards, fail fast and clear.
        if let last = frames.last, timestampSec <= last.timestampSec {
            clear(reason: "non-monotonic timestamps (t=\(fmt(timestampSec)) <= last=\(fmt(last.timestampSec)))")
            // Start fresh (this frame is still eligible).
        }

        // Accept.
        let frame = RSWindowFrame(
            ballCenter2D: ballCenter2D,
            ballRadiusPx: ballRadiusPx,
            timestampSec: timestampSec,
            confidence: confidence,
            rowTiming: rowTiming
        )

        frames.append(frame)

        // Enforce rolling capacity.
        if frames.count > config.capacity {
            frames.removeFirst(frames.count - config.capacity)
        }

        transitionToAccepted(nowSec: timestampSec, confidence: confidence)
        transitionToReadyIfNeeded(nowSec: timestampSec)

        return .accepted(frameCount: frames.count)
    }

    /// Returns an immutable snapshot (validity computed at snapshot time).
    func snapshot(nowSec: Double) -> RSWindowSnapshot {
        RSWindowSnapshot(frames: frames, snapshotTimeSec: nowSec, config: config)
    }

    /// Returns a snapshot only if valid (at nowSec). Clears window if stale.
    func validSnapshot(nowSec: Double) -> RSWindowSnapshot? {
        lastTickSec = nowSec
        _ = clearIfStale(nowSec: nowSec)
        let snap = snapshot(nowSec: nowSec)
        return snap.isValid ? snap : nil
    }

    // MARK: - Internal helpers

    private func clearIfStale(nowSec: Double) -> Bool {
        guard !frames.isEmpty else { return false }
        let stale = (nowSec - (frames.last?.timestampSec ?? nowSec)) > config.maxStalenessSec
        let spanTooLong = windowAgeSec > config.maxSpanSec

        if stale {
            clear(reason: "stale window (staleness=\(fmt(stalenessSec))s > \(fmt(config.maxStalenessSec))s)")
            return true
        }
        if spanTooLong {
            clear(reason: "span too long (span=\(fmt(windowAgeSec))s > \(fmt(config.maxSpanSec))s)")
            return true
        }
        return false
    }

    private func clear(reason: String) {
        frames.removeAll(keepingCapacity: true)

        // Transition-based logging only.
        if DebugProbe.isEnabled(.capture) {
            if lastLoggedClearReason != reason {
                print("[RSWINDOW] cleared (\(reason))")
                lastLoggedClearReason = reason
            }
        }

        logState = .idle
    }

    private func transitionToRejecting(confidence: Float) {
        guard logState != .rejectingLowConfidence else { return }
        logState = .rejectingLowConfidence

        if DebugProbe.isEnabled(.capture) {
            print("[RSWINDOW] rejected (confidence \(fmt(confidence)) < \(fmt(config.confidenceThreshold)))")
        }
    }

    private func transitionToAccepted(nowSec: Double, confidence: Float) {
        // Log acceptance only on transitions (idle/rejecting -> collecting).
        if logState == .idle || logState == .rejectingLowConfidence {
            logState = .collecting
            lastLoggedClearReason = nil

            if DebugProbe.isEnabled(.capture) {
                print("[RSWINDOW] accepted frame t=\(fmt(nowSec)) count=\(frames.count) conf=\(fmt(confidence))")
            }
        }
    }

    private func transitionToReadyIfNeeded(nowSec: Double) {
        guard frames.count >= config.minFrames else { return }
        guard logState != .ready else { return }

        logState = .ready

        if DebugProbe.isEnabled(.capture) {
            print("[RSWINDOW] window ready count=\(frames.count) span=\(fmt(windowAgeSec))s conf(avg=\(fmt(snapshot(nowSec: nowSec).confidenceAvg)))")
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
