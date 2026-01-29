//
//  RSObservabilityProbe.swift
//  LaunchLab
//
//  PHASE 2 → PHASE 3 — Single-frame RS observability
//
//  ROLE (STRICT):
//  - Analyze ONE frame only
//  - No temporal memory
//  - No authority
//  - MUST explain refusals
//

import Foundation
import CoreGraphics

final class RSObservabilityProbe {

    private let minPointCount: Int = 6
    private let minSlope: Float = 0.0001
    private let maxFlickerCorrelation: Float = 0.85

    public enum RowSpanClass: String {
        case narrow
        case moderate
        case wide
    }

    @inline(__always)
    func evaluate(
        points: [CGPoint],
        imageHeight: Int,
        timestamp: Double
    ) -> RSFrameObservation {

        // -----------------------------------------------------
        // Insufficient points
        // -----------------------------------------------------

        guard points.count >= minPointCount else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x50,
                valueA: Float(points.count),
                valueB: 0
            )
            return RSFrameObservation.refused(timestamp, .insufficientRowSupport)
        }

        // -----------------------------------------------------
        // Row energy histogram
        // -----------------------------------------------------

        var rowEnergy: [Int: Int] = [:]
        for p in points {
            rowEnergy[Int(round(p.y)), default: 0] += 1
        }

        let rows = rowEnergy.keys.sorted()
        let rowSpan = rows.last! - rows.first!
        let spanFraction = Float(rowSpan) / Float(max(imageHeight, 1))

        // Adjacent correlation (flicker proxy)
        var adj = 0
        for i in 1..<rows.count {
            if rows[i] == rows[i - 1] + 1 { adj += 1 }
        }

        let rowCorrelation =
            rows.count > 1 ? Float(adj) / Float(rows.count - 1) : 0

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x23,                  // ROW_CORRELATION_METRIC
            valueA: rowCorrelation,
            valueB: Float(rows.count)
        )

        // -----------------------------------------------------
        // Structure ratio (NEW CORE METRIC)
        // -----------------------------------------------------

        let energies = Array(rowEnergy.values)
        let peak = Float(energies.max() ?? 0)
        let mean = Float(energies.reduce(0, +)) / Float(max(energies.count, 1))
        let structureRatio = mean > 0 ? peak / mean : 0

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x22,                  // STRUCTURE_METRIC
            valueA: structureRatio,
            valueB: peak
        )

        // -----------------------------------------------------
        // RS shear (least squares)
        // -----------------------------------------------------

        var sumX: CGFloat = 0, sumY: CGFloat = 0
        var sumXY: CGFloat = 0, sumXX: CGFloat = 0

        for p in points {
            sumX += p.x
            sumY += p.y
            sumXY += p.x * p.y
            sumXX += p.x * p.x
        }

        let n = CGFloat(points.count)
        let denom = (n * sumXX - sumX * sumX)
        let slope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0
        let zmax = Float(abs(slope))

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x20,
            valueA: zmax,
            valueB: Float(points.count)
        )

        // -----------------------------------------------------
        // Row span classification
        // -----------------------------------------------------

        let rowSpanClass: RowSpanClass
        let rowSpanTelemetryCode: UInt16

        if spanFraction < 0.25 {
            rowSpanClass = .narrow
            rowSpanTelemetryCode = 0x61
        } else if spanFraction < 0.65 {
            rowSpanClass = .moderate
            rowSpanTelemetryCode = 0x62
        } else {
            rowSpanClass = .wide
            rowSpanTelemetryCode = 0x63
        }

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: rowSpanTelemetryCode,
            valueA: spanFraction,
            valueB: 0
        )

        // -----------------------------------------------------
        // Classification and outcome
        // -----------------------------------------------------

        if zmax < minSlope {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x53,
                valueA: zmax,
                valueB: 0
            )
            return RSFrameObservation.refused(timestamp, .frameIntegrityFailure)
        }

        if rowCorrelation > maxFlickerCorrelation && structureRatio < 2.0 {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x54,
                valueA: rowCorrelation,
                valueB: structureRatio
            )
            return RSFrameObservation.refused(timestamp, .globalRowCorrelation)
        }

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x55,                // OBSERVABLE
            valueA: zmax,
            valueB: spanFraction
        )

        return RSFrameObservation(
            timestamp: timestamp,
            zmax: zmax,
            structureRatio: structureRatio,
            rowSpanFraction: spanFraction,
            outcome: .observable
        )
    }
}
