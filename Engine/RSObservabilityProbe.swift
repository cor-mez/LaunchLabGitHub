//
//  RSObservabilityProbe.swift
//  LaunchLab
//
//  PHASE 2 — Single-frame RS observability
//
//  ROLE (STRICT):
//  - Analyze ONE frame only
//  - No temporal memory
//  - No authority
//  - MUST return a classified RSFrameObservation
//  - Telemetry MUST explain refusals offline
//

import Foundation
import CoreGraphics

final class RSObservabilityProbe {

    // ---------------------------------------------------------
    // MARK: - Phase‑2 Safe Thresholds
    // ---------------------------------------------------------

    private let minPointCount: Int = 6
    private let minSlope: Float = 0.0001
    private let maxGlobalCorrelation: Float = 0.85

    // ---------------------------------------------------------
    // MARK: - Evaluation
    // ---------------------------------------------------------

    @inline(__always)
    func evaluate(
        points: [CGPoint],
        imageHeight: Int,
        timestamp: Double
    ) -> RSFrameObservation {

        // -----------------------------------------------------
        // REFUSAL 0x50 — insufficient spatial support
        // -----------------------------------------------------

        guard points.count >= minPointCount else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x50,                     // REFUSE_INSUFFICIENT_POINTS
                valueA: Float(points.count),
                valueB: 0
            )

            return RSFrameObservation(
                timestamp: timestamp,
                zmax: 0,
                dz: 0,
                rowCorrelation: 0,
                globalVariance: 0,
                localVariance: 0,
                validRowCount: points.count,
                droppedRows: 0,
                centroid: nil,
                envelopeRadius: nil,
                outcome: .refused(.insufficientRowSupport)
            )
        }

        // -----------------------------------------------------
        // Row‑energy histogram (row → count)
        // -----------------------------------------------------

        var rowEnergy: [Int: Int] = [:]
        rowEnergy.reserveCapacity(points.count)

        for p in points {
            let row = Int(round(p.y))
            rowEnergy[row, default: 0] += 1
        }

        let activeRows = rowEnergy.keys.sorted()
        let rowSpan = activeRows.last! - activeRows.first!
        let rowSpanFraction =
            Float(rowSpan) / Float(max(imageHeight, 1))

        // -----------------------------------------------------
        // Intra-span structure metric
        // -----------------------------------------------------

        let peakRowEnergy = rowEnergy.values.max() ?? 0
        let meanRowEnergy = rowEnergy.values.reduce(0, +) / max(rowEnergy.count, 1)
        let structureRatio = Float(peakRowEnergy) / Float(max(meanRowEnergy, 1))

        enum RowSpanClass: UInt16 {
            case narrow = 0x61
            case moderate = 0x62
            case wide = 0x63
        }

        let spanClass: RowSpanClass
        if rowSpanFraction < 0.25 {
            spanClass = .narrow
        } else if rowSpanFraction < 0.70 {
            spanClass = .moderate
        } else {
            spanClass = .wide
        }

        // -----------------------------------------------------
        // Adjacent‑row correlation (global flicker proxy)
        // -----------------------------------------------------

        var correlatedPairs = 0
        for i in 1..<activeRows.count {
            if activeRows[i] == activeRows[i - 1] + 1 {
                correlatedPairs += 1
            }
        }

        let adjacentRowCorrelation: Float =
            activeRows.count > 1
            ? Float(correlatedPairs) / Float(activeRows.count - 1)
            : 0

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: spanClass.rawValue,
            valueA: rowSpanFraction,
            valueB: adjacentRowCorrelation
        )
        
        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x22,                        // RS_STRUCTURE_METRIC
            valueA: Float(structureRatio),
            valueB: Float(peakRowEnergy)
        )

        // -----------------------------------------------------
        // Least‑squares slope (RS shear proxy)
        // -----------------------------------------------------

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var sumXY: CGFloat = 0
        var sumXX: CGFloat = 0

        for p in points {
            sumX += p.x
            sumY += p.y
            sumXY += p.x * p.y
            sumXX += p.x * p.x
        }

        let n = CGFloat(points.count)
        let denom = (n * sumXX - sumX * sumX)

        let slope: CGFloat = denom != 0
            ? (n * sumXY - sumX * sumY) / denom
            : 0

        let zmax = Float(abs(slope))

        // -----------------------------------------------------
        // Spatial anchoring
        // -----------------------------------------------------

        let centroid = CGPoint(x: sumX / n, y: sumY / n)

        let envelopeRadius = Float(
            points
                .map { hypot($0.x - centroid.x, $0.y - centroid.y) }
                .max() ?? 0
        )

        // -----------------------------------------------------
        // Telemetry — raw observables (offline truth)
        // -----------------------------------------------------

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x20,                        // RS_RAW_METRICS
            valueA: zmax,
            valueB: Float(points.count)
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x21,                        // RS_LOCALITY_METRICS
            valueA: rowSpanFraction,
            valueB: adjacentRowCorrelation
        )

        // -----------------------------------------------------
        // Classification (refusal‑first, explainable)
        // -----------------------------------------------------

        let outcome: RSObservationOutcome

        // REFUSAL 0x53 — slope too small
        if zmax < minSlope {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x53,                    // REFUSE_LOW_SLOPE
                valueA: zmax,
                valueB: 0
            )
            outcome = .refused(.frameIntegrityFailure)

        // REFUSAL 0x54 — adjacent‑row correlation (flicker‑like)
        } else if adjacentRowCorrelation > maxGlobalCorrelation {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x54,                    // REFUSE_FLICKER_ALIGNED
                valueA: adjacentRowCorrelation,
                valueB: 0
            )
            outcome = .refused(.globalRowCorrelation)

        // ACCEPT — observable RS smear (may be wide-span)
        } else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x55,                    // RS_OBSERVABLE
                valueA: zmax,
                valueB: rowSpanFraction
            )
            outcome = .observable
        }

        // -----------------------------------------------------
        // Immutable frame observation
        // -----------------------------------------------------

        return RSFrameObservation(
            timestamp: timestamp,
            zmax: zmax,
            dz: 0,                              // Phase‑2: no temporal derivative
            rowCorrelation: adjacentRowCorrelation,
            globalVariance: Float(rowSpan),
            localVariance: envelopeRadius,
            validRowCount: activeRows.count,
            droppedRows: 0,
            centroid: centroid,
            envelopeRadius: envelopeRadius,
            outcome: outcome
        )
    }
}
