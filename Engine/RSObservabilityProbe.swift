//
//  RSObservabilityProbe.swift
//  LaunchLab
//
//  PHASE 2 — Single-frame RS observability
//
//  ROLE (STRICT):
//  - Analyze ONE frame only
//  - No temporal memory
//  - No decisions (no authority)
//  - No logging
//  - MUST return a classified RSFrameObservation (observable OR refused(reason))
//  - Telemetry is optional and must be allocation-free
//

import Foundation
import CoreGraphics

final class RSObservabilityProbe {

    @inline(__always)
    func evaluate(
        points: [CGPoint],
        imageHeight: Int,
        timestamp: Double
    ) -> RSFrameObservation {

        // Minimum spatial support
        guard points.count >= 6 else {
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

        // Least squares slope y vs x (proxy)
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

        // Local variance proxy
        let meanY = sumY / n
        let localVar = points.reduce(CGFloat(0)) { acc, p in
            acc + pow(p.y - meanY, 2)
        } / n
        let localVariance = Float(localVar)

        // Global dominance proxy (placeholder until flicker coupling is added)
        let rowCorrelation: Float = (zmax > 0.0005) ? 1.0 : 0.0

        // Spatial anchoring
        let centroid = CGPoint(x: sumX / n, y: sumY / n)
        let envelopeRadius = Float(points.map { hypot($0.x - centroid.x, $0.y - centroid.y) }.max() ?? 0)

        // Mandatory classification — no fallthrough
        let outcome: RSObservationOutcome
        if rowCorrelation > 0.90 {
            outcome = .refused(.globalRowCorrelation)
        } else if envelopeRadius <= 0 {
            outcome = .refused(.localityUnstable)
        } else if zmax < 0.0005 {
            outcome = .refused(.frameIntegrityFailure)
        } else {
            outcome = .observable
        }

        // Allocation-free telemetry (optional)
        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x20,
            valueA: zmax,
            valueB: localVariance
        )

        return RSFrameObservation(
            timestamp: timestamp,
            zmax: zmax,
            dz: zmax, // single-frame proxy
            rowCorrelation: rowCorrelation,
            globalVariance: localVariance, // placeholder until split
            localVariance: localVariance,
            validRowCount: points.count,
            droppedRows: 0,
            centroid: centroid,
            envelopeRadius: envelopeRadius,
            outcome: outcome
        )
    }
}
