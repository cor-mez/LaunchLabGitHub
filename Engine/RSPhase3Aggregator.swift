import Foundation

/// Concrete Phase-3 temporal aggregator.
/// Implements the Phase-3 contract defined in RSWindowAggregator.swift
final class RSPhase3Aggregator: RSPhase3Aggregating {

    // ---------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------

    private let maxWindowFrames = 8
    private let minWindowFrames = 3

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []
    private var lastEmissionTime: Double?

    // ---------------------------------------------------------
    // Ingest
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {
        buffer.append(frame)

        // Hard cap to avoid unbounded growth
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

        let times = buffer.map { $0.timestamp }
        let zvals = buffer.map { $0.zmax }

        let zmaxPeak = zvals.max() ?? 0
        let zmaxMedian = zvals.sorted()[zvals.count / 2]

        let structuredFrames = buffer.filter {
            $0.outcome == .observable
        }.count

        let wideSpanCount = buffer.filter {
            $0.rowSpanFraction >= 0.75
        }.count

        let observation = RSWindowObservation(
            startTime: times.first ?? 0,
            endTime: times.last ?? 0,
            frameCount: buffer.count,
            zmaxPeak: zmaxPeak,
            zmaxMedian: zmaxMedian,
            structuredFrameCount: structuredFrames,
            wideSpanFraction: Float(wideSpanCount) / Float(buffer.count),
            temporalConsistency: Float(structuredFrames) / Float(buffer.count),
            structureConsistency: 1.0, // placeholder, Phase-3 safe
            outcome: structuredFrames > 0 ? .structuredMotion : .noiseLike
        )

        buffer.removeAll()
        return observation
    }

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
        lastEmissionTime = nil
    }
}
