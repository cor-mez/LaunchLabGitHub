//
//  RSPhase3Aggregator.swift
//  LaunchLab
//
//  PHASE 3 — Temporal RS Envelope Aggregation (IMPLEMENTATION)
//
//  ROLE (STRICT):
//  - Aggregate short runs of Phase-2 RSFrameObservation
//  - Describe temporal RS envelopes
//  - Observability-only (no authority)
//  - NO shot decisions
//  - NO smoothing
//  - NO thresholds enforced here
//

import Foundation

/// Concrete Phase-3 temporal aggregator.
/// Implements the Phase-3 contract defined in RSWindowAggregator.swift
final class RSPhase3Aggregator: RSPhase3Aggregating {

    // ---------------------------------------------------------
    // Configuration (Phase-3 safe defaults)
    // ---------------------------------------------------------

    /// Maximum number of frames retained in a temporal window
    private let maxWindowFrames: Int = 8

    /// Minimum frames required to emit a window
    private let minWindowFrames: Int = 3

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []
    private var lastEmittedWindow: RSWindowObservation?

    // ---------------------------------------------------------
    // Ingest
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {
        switch frame.outcome {
        case .observable:
            // Append observable frames to buffer
            buffer.append(frame)
            // Hard cap to prevent unbounded growth
            if buffer.count > maxWindowFrames {
                buffer.removeFirst()
            }
            // No window emitted on observable frames
            lastEmittedWindow = nil

        case .refused:
            // Emit window only if we have enough observable frames accumulated
            if buffer.count >= minWindowFrames {
                let window = createWindowObservation(from: buffer)
                lastEmittedWindow = window
                buffer.removeAll()
            } else {
                // Not enough frames to emit window, reset silently
                buffer.removeAll()
                lastEmittedWindow = nil
            }
        }
    }

    // ---------------------------------------------------------
    // Poll
    // ---------------------------------------------------------

    func poll() -> RSWindowObservation? {
        // Return the last emitted window once, then clear it
        guard let window = lastEmittedWindow else {
            return nil
        }
        lastEmittedWindow = nil
        return window
    }

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
        lastEmittedWindow = nil
    }

    // ---------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------

    /// Create a RSWindowObservation from a buffer of RSFrameObservation
    /// This encapsulates the existing descriptive metrics calculation.
    private func createWindowObservation(from frames: [RSFrameObservation]) -> RSWindowObservation {
        let times = frames.map { $0.timestamp }
        let zvals = frames.map { $0.zmax }.sorted()

        let zmaxPeak = zvals.last ?? 0
        let zmaxMedian = zvals[zvals.count / 2]

        // -----------------------------------------------------
        // Structured frames
        // -----------------------------------------------------

        let structuredFrameCount = frames.filter {
            if case .observable = $0.outcome {
                return true
            }
            return false
        }.count

        // -----------------------------------------------------
        // Row-span composition (DESCRIPTIVE)
        // -----------------------------------------------------

        let narrowSpanCount = frames.filter {
            $0.rowSpanFraction < 0.40
        }.count

        let moderateSpanCount = frames.filter {
            $0.rowSpanFraction >= 0.40 && $0.rowSpanFraction < 0.75
        }.count

        let wideSpanCount = frames.filter {
            $0.rowSpanFraction >= 0.75
        }.count

        let wideSpanFraction =
            Float(wideSpanCount) / Float(frames.count)

        // -----------------------------------------------------
        // Coherence metrics (DESCRIPTIVE)
        // -----------------------------------------------------

        let temporalConsistency =
            Float(structuredFrameCount) / Float(frames.count)

        // Structure consistency is intentionally deferred to Phase-4
        let structureConsistency: Float = 1.0

        // -----------------------------------------------------
        // Outcome (DESCRIPTIVE ONLY)
        // -----------------------------------------------------

        let outcome: RSWindowOutcome
        if structuredFrameCount == 0 {
            outcome = .noiseLike
        } else {
            outcome = .structuredMotion
        }

        return RSWindowObservation(
            startTime: times.first ?? 0,
            endTime: times.last ?? 0,
            frameCount: frames.count,

            zmaxPeak: zmaxPeak,
            zmaxMedian: zmaxMedian,
            structuredFrameCount: structuredFrameCount,

            narrowSpanCount: narrowSpanCount,
            moderateSpanCount: moderateSpanCount,
            wideSpanCount: wideSpanCount,
            wideSpanFraction: wideSpanFraction,

            temporalConsistency: temporalConsistency,
            structureConsistency: structureConsistency,

            outcome: outcome
        )
    }
}
