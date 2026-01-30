//
//  RSPhase3Aggregator.swift
//  LaunchLab
//
//  PHASE 3 — Temporal RS aggregation (OBSERVABILITY ONLY)
//
//  ROLE (STRICT):
//  - Aggregate short RS bursts
//  - Describe temporal envelopes
//  - NO authority
//  - NO lifecycle decisions
//  - NO smoothing
//

import Foundation
import QuartzCore

final class RSPhase3Aggregator: RSPhase3Aggregating {

    // ---------------------------------------------------------
    // Configuration (Phase‑3 safe defaults)
    // ---------------------------------------------------------

    private let maxWindowFrames: Int = 8
    private let minWindowFrames: Int = 3

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------

    private var buffer: [RSFrameObservation] = []
    private var pendingWindow: RSWindowObservation?

    // ---------------------------------------------------------
    // Ingest
    // ---------------------------------------------------------

    func ingest(_ frame: RSFrameObservation) {

        switch frame.outcome {

        case .observable:
            buffer.append(frame)

            // Emit a window when we hit capacity
            if buffer.count >= maxWindowFrames {
                pendingWindow = buildWindow(from: buffer)
                buffer.removeAll()
            }

        case .refused:
            // Emit a window if we have enough accumulated signal
            if buffer.count >= minWindowFrames {
                pendingWindow = buildWindow(from: buffer)
            }
            buffer.removeAll()
        }
    }

    // ---------------------------------------------------------
    // Poll
    // ---------------------------------------------------------

    func poll() -> RSWindowObservation? {
        guard let window = pendingWindow else {
            return nil
        }

        pendingWindow = nil

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x80,                    // PHASE3_WINDOW_SUMMARY
            valueA: window.zmaxPeak,
            valueB: window.temporalConsistency
        )

        return window
    }

    // ---------------------------------------------------------
    // Reset
    // ---------------------------------------------------------

    func reset() {
        buffer.removeAll()
        pendingWindow = nil
    }

    // ---------------------------------------------------------
    // Window Construction (DESCRIPTIVE ONLY)
    // ---------------------------------------------------------

    private func buildWindow(from frames: [RSFrameObservation]) -> RSWindowObservation {

        let times = frames.map { $0.timestamp }
        let zvals = frames.map { $0.zmax }.sorted()

        let zmaxPeak = zvals.last ?? 0
        let zmaxMedian = zvals[zvals.count / 2]

        let structuredCount = frames.filter {
            if case .observable = $0.outcome { return true }
            return false
        }.count

        let narrowSpanCount = frames.filter { $0.rowSpanFraction < 0.33 }.count
        let moderateSpanCount = frames.filter {
            $0.rowSpanFraction >= 0.33 && $0.rowSpanFraction < 0.75
        }.count
        let wideSpanCount = frames.filter { $0.rowSpanFraction >= 0.75 }.count

        let wideSpanFraction = Float(wideSpanCount) / Float(frames.count)
        let temporalConsistency = Float(structuredCount) / Float(frames.count)

        let outcome: RSWindowOutcome =
            structuredCount == 0 ? .noiseLike : .structuredMotion

        return RSWindowObservation(
            startTime: times.first ?? 0,
            endTime: times.last ?? 0,
            frameCount: frames.count,
            zmaxPeak: zmaxPeak,
            zmaxMedian: zmaxMedian,
            structuredFrameCount: structuredCount,
            narrowSpanCount: narrowSpanCount,
            moderateSpanCount: moderateSpanCount,
            wideSpanCount: wideSpanCount,
            wideSpanFraction: wideSpanFraction,
            temporalConsistency: temporalConsistency,
            structureConsistency: 1.0,   // Phase‑4 computes this
            outcome: outcome
        )
    }
}
