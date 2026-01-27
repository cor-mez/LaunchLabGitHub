//
//  RSWindowAggregatorImpl.swift
//  LaunchLab
//
//  PHASE 3 — Temporal RS Envelope Aggregation (IMPLEMENTATION)
//
//  ROLE (STRICT):
//  - Aggregate Phase-2 RSFrameObservation frames
//  - Describe short RS bursts over time
//  - Observability-only
//  - NO authority
//  - NO shot decisions
//  - NO smoothing
//

import Foundation

final class RSWindowAggregatorImpl: RSPhase3Aggregating {

    // ---------------------------------------------------------
    // Configuration (Phase-3 safe defaults)
    // ---------------------------------------------------------

    private let maxWindowFrames: Int = 8
    private let minWindowFrames: Int = 3

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []

    // ---------------------------------------------------------
    // Ingest Phase-2 frames
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {

        // Phase-3 ingests *all* frames
        // (observable + refused), but only aggregates observables
        if case .observable = frame.outcome {
            buffer.append(frame)
        } else {
            flushIfReady()
        }

        if buffer.count >= maxWindowFrames {
            flushIfReady()
        }
    }

    // ---------------------------------------------------------
    // Poll aggregated window
    // ---------------------------------------------------------

    func poll() -> RSWindowObservation? {
        // Aggregation happens eagerly during ingest
        // poll() is intentionally passive
        return nil
    }

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
    }

    // ---------------------------------------------------------
    // Window aggregation
    // ---------------------------------------------------------

    private func flushIfReady() {

        guard buffer.count >= minWindowFrames else {
            buffer.removeAll()
            return
        }

        let frames = buffer
        buffer.removeAll()

        emitWindowObservation(from: frames)
    }

    // ---------------------------------------------------------
    // Build RSWindowObservation
    // ---------------------------------------------------------

    private func emitWindowObservation(from frames: [RSFrameObservation]) {

        let startTime = frames.first!.timestamp
        let endTime   = frames.last!.timestamp

        let zValues = frames.map { $0.zmax }
        let zPeak   = zValues.max() ?? 0
        let zMedian = zValues.sorted()[zValues.count / 2]

        let structuredFrames = frames.filter {
            // Phase-2 provides explicit structure ratio
            $0.structureRatio > 1.0
        }.count

        let wideSpanFrames = frames.filter {
            // Wide span = physically smeared RS envelope
            $0.rowSpanFraction >= 0.75
        }.count

        let wideSpanFraction =
            Float(wideSpanFrames) / Float(frames.count)

        // Temporal consistency: how continuous the burst is
        let temporalConsistency =
            Float(frames.count) / Float(maxWindowFrames)

        // Structure consistency: proportion of structured frames
        let structureConsistency =
            Float(structuredFrames) / Float(frames.count)

        let outcome: RSWindowOutcome

        if frames.count < minWindowFrames {
            outcome = .insufficientData
        } else if structureConsistency < 0.3 {
            outcome = .noiseLike
        } else {
            outcome = .structuredMotion
        }

        let window = RSWindowObservation(
            startTime: startTime,
            endTime: endTime,
            frameCount: frames.count,
            zmaxPeak: zPeak,
            zmaxMedian: zMedian,
            structuredFrameCount: structuredFrames,
            wideSpanFraction: wideSpanFraction,
            temporalConsistency: temporalConsistency,
            structureConsistency: structureConsistency,
            outcome: outcome
        )

        emitTelemetry(window)
    }

    // ---------------------------------------------------------
    // Telemetry (explainable, non-authoritative)
    // ---------------------------------------------------------

    private func emitTelemetry(_ window: RSWindowObservation) {

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x80,                  // PHASE3_WINDOW_SUMMARY
            valueA: window.zmaxPeak,
            valueB: window.structureConsistency
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x81,                  // PHASE3_WINDOW_SPAN
            valueA: window.wideSpanFraction,
            valueB: Float(window.frameCount)
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x82,                  // PHASE3_WINDOW_OUTCOME
            valueA: outcomeCode(window.outcome),
            valueB: window.temporalConsistency
        )

        // ---------------------------------------------------------
        // Phase-4 gating (window-level, observability only)
        // ---------------------------------------------------------

        let verdict = RSPhase4Gate.evaluate(window)

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: verdict == .pass ? 0x90 : 0x91,   // PHASE4_PASS / PHASE4_FAIL
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
