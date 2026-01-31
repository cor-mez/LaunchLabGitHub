//
//  RSWindowAggregatorImpl.swift
//  LaunchLab
//
//  PHASE 3 — Temporal RS Envelope Aggregation (IMPLEMENTATION)
//
//  ROLE (STRICT):
//  - Aggregate Phase‑2 RSFrameObservation frames
//  - Describe short RS bursts over time
//  - Observability‑only
//  - NO authority
//  - NO shot decisions
//  - NO smoothing
//

import Foundation

final class RSWindowAggregatorImpl: RSPhase3Aggregating {

    // ---------------------------------------------------------
    // Configuration (Phase‑3 safe defaults)
    // ---------------------------------------------------------

    private let maxWindowFrames: Int = 8
    private let minWindowFrames: Int = 3
    private let maxGapSec: Double = 0.025

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []
    private var pendingWindow: RSWindowObservation?
    private var lastTimestamp: Double?

    // ---------------------------------------------------------
    // Ingest Phase‑2 frames
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {

        // If there is a time gap, treat it as a burst boundary.
        if let last = lastTimestamp {
            let dt = frame.timestamp - last
            if dt > maxGapSec {
                flushIfReady()
                buffer.removeAll()
            }
        }
        lastTimestamp = frame.timestamp

        // Always keep a rolling buffer
        buffer.append(frame)

        // Hard cap buffer size
        if buffer.count > maxWindowFrames {
            buffer.removeFirst()
        }

        // Burst termination triggers (no smoothing):
        //  - buffer full
        //  - an explicit refusal arrives
        if buffer.count >= maxWindowFrames {
            flushIfReady()
            buffer.removeAll()
            return
        }

        if case .refused = frame.outcome {
            flushIfReady()
            buffer.removeAll()
            return
        }
    }

    // ---------------------------------------------------------
    // Poll aggregated window
    // ---------------------------------------------------------

    func poll() -> RSWindowObservation? {
        let w = pendingWindow
        pendingWindow = nil
        return w
    }

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
        pendingWindow = nil
        lastTimestamp = nil
    }

    // ---------------------------------------------------------
    // Flush logic
    // ---------------------------------------------------------

    private func flushIfReady() {

        guard !buffer.isEmpty else { return }

        // Only emit if we have enough observable frames within the burst.
        let observableCount = buffer.filter {
            if case .observable = $0.outcome { return true }
            return false
        }.count

        let observableFrames = buffer.filter {
            if case .observable = $0.outcome { return true }
            return false
        }

        guard observableCount >= minWindowFrames else {
            return
        }

        let startTime = buffer.first!.timestamp
        let endTime = buffer.last!.timestamp

        let window = buildWindow(from: observableFrames, startTime: startTime, endTime: endTime)
        pendingWindow = window
        emitTelemetry(window)
    }

    // ---------------------------------------------------------
    // Window construction
    // ---------------------------------------------------------

    private func buildWindow(
        from frames: [RSFrameObservation],
        startTime: Double,
        endTime: Double
    ) -> RSWindowObservation {

        let zValues = frames.map { $0.zmax }
        let zPeak = zValues.max() ?? 0
        let zMedian = zValues.sorted()[zValues.count / 2]

        let structuredFrames = frames.count

        let narrowSpanCount = frames.filter { $0.rowSpanFraction < 0.40 }.count
        let moderateSpanCount = frames.filter { $0.rowSpanFraction >= 0.40 && $0.rowSpanFraction < 0.75 }.count
        let wideSpanCount = frames.filter { $0.rowSpanFraction >= 0.75 }.count

        let wideSpanFraction = Float(wideSpanCount) / Float(frames.count)

        // Temporal consistency here is a descriptive metric: fraction of max window occupied.
        let temporalConsistency = min(1.0, Float(frames.count) / Float(maxWindowFrames))

        // Structure consistency: fraction of frames in this window that are structured (observable).
        let structureConsistency: Float = 1.0

        let outcome: RSWindowOutcome
        if frames.count < minWindowFrames {
            outcome = .insufficientData
        } else if structuredFrames == 0 {
            outcome = .noiseLike
        } else {
            outcome = .structuredMotion
        }

        return RSWindowObservation(
            startTime: startTime,
            endTime: endTime,
            frameCount: frames.count,
            zmaxPeak: zPeak,
            zmaxMedian: zMedian,
            structuredFrameCount: structuredFrames,
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
    // Telemetry (explainable, non‑authoritative)
    // ---------------------------------------------------------

    private func emitTelemetry(_ window: RSWindowObservation) {

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x80,                 // PHASE3_WINDOW_SUMMARY
            valueA: window.zmaxPeak,
            valueB: window.structureConsistency
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x81,                 // PHASE3_WINDOW_SPAN
            valueA: window.wideSpanFraction,
            valueB: Float(window.frameCount)
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x82,                 // PHASE3_WINDOW_OUTCOME
            valueA: outcomeCode(window.outcome),
            valueB: window.temporalConsistency
        )

        let verdict = RSPhase4Gate.evaluate(window)

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: verdict == .pass ? 0x90 : 0x91,
            valueA: window.zmaxPeak,
            valueB: window.structureConsistency
        )
    }

    private func outcomeCode(_ outcome: RSWindowOutcome) -> Float {
        switch outcome {
        case .insufficientData: return 0
        case .noiseLike:        return 1
        case .structuredMotion:return 2
        }
    }
}
