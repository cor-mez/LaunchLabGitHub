//
//  RSObservabilityProbe.swift
//  LaunchLab
//
//  PHASE 2 — Single-frame RS observability
//
//  ROLE (STRICT):
//  - Analyze ONE frame only
//  - No temporal memory
//  - No decisions
//  - No logging
//  - MUST return a classified RSFrameObservation
//

import Foundation
import CoreGraphics

final class RSObservabilityProbe {

    // Tunable, but conservative defaults
    private let minSlope: Float = 0.0005
    private let minEnvelopeRadius: Float = 3.0

    @inline(__always)
    func evaluate(
        points: [CGPoint],
        imageHeight: Int,
        timestamp: Double
    ) -> RSFrameObservation {

        // -----------------------------------------------------
        // Guard: minimum spatial support
        // -----------------------------------------------------
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

        // -----------------------------------------------------
        // Least-squares row slope (sub-pixel)
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
        // Local variance (RS energy proxy)
        // -----------------------------------------------------
        let meanY = sumY / n
        let localVar = points.reduce(CGFloat(0)) {
            $0 + pow($1.y - meanY, 2)
        } / n

        let localVariance = Float(localVar)

        // -----------------------------------------------------
        // Spatial anchoring
        // -----------------------------------------------------
        let centroid = CGPoint(
            x: sumX / n,
            y: sumY / n
        )

        let envelopeRadius = Float(
            points
                .map { hypot($0.x - centroid.x, $0.y - centroid.y) }
                .max() ?? 0
        )

        // -----------------------------------------------------
        // Classification (NO AUTO-REFUSAL)
        // -----------------------------------------------------
        let outcome: RSObservationOutcome

        if zmax < minSlope {
            outcome = .refused(.frameIntegrityFailure)

        } else if envelopeRadius < minEnvelopeRadius {
            outcome = .refused(.localityUnstable)

        } else {
            // IMPORTANT:
            // This is the FIRST TIME .observable is reachable
            outcome = .observable
        }

        // -----------------------------------------------------
        // Telemetry (facts only)
        // -----------------------------------------------------
        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x20,              // RS frame evaluated
            valueA: zmax,
            valueB: Float(points.count)
        )

        // -----------------------------------------------------
        // Immutable observation
        // -----------------------------------------------------
        return RSFrameObservation(
            timestamp: timestamp,
            zmax: zmax,
            dz: zmax,
            rowCorrelation: 0,        // intentionally unused in this round
            globalVariance: localVariance,
            localVariance: localVariance,
            validRowCount: points.count,
            droppedRows: 0,
            centroid: centroid,
            envelopeRadius: envelopeRadius,
            outcome: outcome
        )
    }
}
