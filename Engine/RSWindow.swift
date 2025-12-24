//
//  RSWindow.swift
//  Rolling-Shutter Observation Window (Logging-Cleaned)
//

import Foundation
import CoreGraphics

// MARK: - RSWindow
// Rolling-shutter observation window (confidence-gated, read-only consumer).

/// Optional rolling-shutter timing metadata for a frame.
struct RSRowTiming: Equatable {
    let imageHeightPx: Int
    let readoutTimeSec: Double?
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
    var capacity: Int = 5
    var minFrames: Int = 3
    var confidenceThreshold: Float = 12.0
    var maxStalenessSec: Double = 0.25
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

/// Immutable snapshot passed into solvers.
struct RSWindowSnapshot: Equatable {
    let frames: [RSWindowFrame]
    let snapshotTimeSec: Double
    let config: RSWindowConfig

    var frameCount: Int { frames.count }

    var spanSec: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return max(0, last.timestampSec - first.timestampSec)
    }

    var stalenessSec: Double {
        guard let last = frames.last else { return .infinity }
        return max(0, snapshotTimeSec - last.timestampSec)
    }

    var confidenceAvg: Float {
        guard !frames.isEmpty else { return 0 }
        return frames.reduce(0) { $0 + $1.confidence } / Float(frames.count)
    }

    var isValid: Bool {
        guard frameCount >= config.minFrames else { return false }
        guard stalenessSec <= config.maxStalenessSec else { return false }
        guard spanSec <= config.maxSpanSec else { return false }
        return true
    }
}

/// Ingest decision (solver throttling).
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

    // MARK: - Public

    var frameCount: Int { frames.count }

    var windowAgeSec: Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        return max(0, last.timestampSec - first.timestampSec)
    }

    var stalenessSec: Double {
        guard let last = frames.last else { return .infinity }
        return max(0, lastTickSec - last.timestampSec)
    }

    var isValid: Bool {
        guard frames.count >= config.minFrames else { return false }
        guard stalenessSec <= config.maxStalenessSec else { return false }
        guard windowAgeSec <= config.maxSpanSec else { return false }
        return true
    }

    @discardableResult
    func ingest(
        ballCenter2D: CGPoint,
        ballRadiusPx: CGFloat,
        timestampSec: Double,
        confidence: Float,
        rowTiming: RSRowTiming? = nil
    ) -> RSWindowIngestDecision {

        lastTickSec = timestampSec
        _ = clearIfStale(nowSec: timestampSec)

        guard confidence >= config.confidenceThreshold else {
            transitionToRejecting(confidence: confidence)
            return .rejectedLowConfidence(confidence: confidence, threshold: config.confidenceThreshold)
        }

        if let last = frames.last, timestampSec <= last.timestampSec {
            clear(reason: "non-monotonic timestamps")
        }

        frames.append(
            RSWindowFrame(
                ballCenter2D: ballCenter2D,
                ballRadiusPx: ballRadiusPx,
                timestampSec: timestampSec,
                confidence: confidence,
                rowTiming: rowTiming
            )
        )

        if frames.count > config.capacity {
            frames.removeFirst(frames.count - config.capacity)
        }

        transitionToAccepted(nowSec: timestampSec, confidence: confidence)
        transitionToReadyIfNeeded(nowSec: timestampSec)

        return .accepted(frameCount: frames.count)
    }

    func snapshot(nowSec: Double) -> RSWindowSnapshot {
        RSWindowSnapshot(frames: frames, snapshotTimeSec: nowSec, config: config)
    }

    func validSnapshot(nowSec: Double) -> RSWindowSnapshot? {
        lastTickSec = nowSec
        _ = clearIfStale(nowSec: nowSec)
        let snap = snapshot(nowSec: nowSec)
        return snap.isValid ? snap : nil
    }

    // MARK: - Internal

    private func clearIfStale(nowSec: Double) -> Bool {
        guard !frames.isEmpty else { return false }

        if stalenessSec > config.maxStalenessSec {
            clear(reason: "stale window")
            return true
        }

        if windowAgeSec > config.maxSpanSec {
            clear(reason: "span too long")
            return true
        }

        return false
    }

    private func clear(reason: String) {
        frames.removeAll(keepingCapacity: true)

        if DebugProbe.isEnabled(.capture), lastLoggedClearReason != reason {
            Log.info(.shot, "RSWINDOW cleared (\(reason))")
            lastLoggedClearReason = reason
        }

        logState = .idle
    }

    private func transitionToRejecting(confidence: Float) {
        guard logState != .rejectingLowConfidence else { return }
        logState = .rejectingLowConfidence

        if DebugProbe.isEnabled(.capture) {
            Log.info(
                .shot,
                "RSWINDOW rejected confidence \(fmt(confidence)) < \(fmt(config.confidenceThreshold))"
            )
        }
    }

    private func transitionToAccepted(nowSec: Double, confidence: Float) {
        if logState == .idle || logState == .rejectingLowConfidence {
            logState = .collecting
            lastLoggedClearReason = nil

            if DebugProbe.isEnabled(.capture) {
                Log.info(
                    .shot,
                    "RSWINDOW accepted t=\(fmt(nowSec)) count=\(frames.count) conf=\(fmt(confidence))"
                )
            }
        }
    }

    private func transitionToReadyIfNeeded(nowSec: Double) {
        guard frames.count >= config.minFrames else { return }
        guard logState != .ready else { return }

        logState = .ready

        if DebugProbe.isEnabled(.capture) {
            Log.info(
                .shot,
                "RSWINDOW ready count=\(frames.count) span=\(fmt(windowAgeSec))s conf(avg=\(fmt(snapshot(nowSec: nowSec).confidenceAvg)))"
            )
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
    private func fmt(_ v: Float) -> String { String(format: "%.2f", v) }
}
