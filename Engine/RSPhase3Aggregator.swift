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

    // ---------------------------------------------------------
    // Ingest
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {

        buffer.append(frame)

        // Hard cap to prevent unbounded growth
        if buffer.count > maxWindowFrames {
            buffer.removeFirst()
        }
    }

    // ---------------------------------------------------------
    // Poll
    // ---------------------------------------------------------

    func poll() -> RSWindowObservation? {

        guard buffer.count >= minWindowFrames else {
            return nil
        }

        let frames = buffer
        buffer.removeAll()

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

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
    }
}
