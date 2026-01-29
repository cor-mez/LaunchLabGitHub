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
    private let minWindowFrames: Int = 1

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []
    private var pendingWindow: RSWindowObservation?

    // ---------------------------------------------------------
    // Ingest Phase‑2 frames
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {
        switch frame.outcome {
        case .observable:
            buffer.append(frame)
            if buffer.count >= maxWindowFrames {
                flushIfReady()
            }
        case .refused:
            flushIfReady()
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
    }

    // ---------------------------------------------------------
    // Flush logic
    // ---------------------------------------------------------

    private func flushIfReady() {
        guard buffer.count >= minWindowFrames else {
            buffer.removeAll()
            return
        }

        let frames = buffer
        buffer.removeAll()

        let window = buildWindow(from: frames)
        pendingWindow = window
        emitTelemetry(window)
    }

    // ---------------------------------------------------------
    // Window construction
    // ---------------------------------------------------------

    private func buildWindow(from frames: [RSFrameObservation]) -> RSWindowObservation {

        let startTime = frames.first!.timestamp
        let endTime   = frames.last!.timestamp

        let zValues = frames.map { $0.zmax }
        let zPeak   = zValues.max() ?? 0
        let zMedian = zValues.sorted()[zValues.count / 2]

        let structuredFrames = frames.filter {
            if case .observable = $0.outcome { return true }
            return false
        }.count

        let narrowSpanCount = frames.filter { $0.rowSpanFraction < 0.40 }.count
        let moderateSpanCount = frames.filter { $0.rowSpanFraction >= 0.40 && $0.rowSpanFraction < 0.75 }.count
        let wideSpanCount = frames.filter { $0.rowSpanFraction >= 0.75 }.count

        let wideSpanFraction =
            Float(wideSpanCount) / Float(frames.count)

        let temporalConsistency =
            min(1.0, Float(frames.count) / Float(maxWindowFrames))

        let structureConsistency =
            Float(structuredFrames) / Float(frames.count)

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
