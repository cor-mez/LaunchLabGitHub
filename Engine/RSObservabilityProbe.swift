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
//  - Emits telemetry facts only
//

import CoreGraphics

// -----------------------------------------------------------------------------
// Phase-2 specific observation (DO NOT CONFUSE WITH ENGINE RSFrameObservation)
// -----------------------------------------------------------------------------

struct RSFrameProbeObservation {

    let rowSlope: Float
    let nonUniformity: Float
    let edgeEnergy: Float
    let valid: Bool
}

final class RSObservabilityProbe {

    @inline(__always)
    func evaluate(
        points: [CGPoint],
        imageHeight: Int
    ) -> RSFrameProbeObservation {

        guard points.count >= 6 else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x01   // insufficient points
            )
            return RSFrameProbeObservation(
                rowSlope: 0,
                nonUniformity: 0,
                edgeEnergy: 0,
                valid: false
            )
        }

        // ---------------------------------------------------------
        // Row slope (least squares y vs x)
        // ---------------------------------------------------------

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

        // ---------------------------------------------------------
        // Non-uniformity (row variance proxy)
        // ---------------------------------------------------------

        let meanY = sumY / n
        let variance = points.reduce(0) {
            $0 + pow($1.y - meanY, 2)
        } / n

        // ---------------------------------------------------------
        // Edge energy proxy (slope × population)
        // ---------------------------------------------------------

        let edgeEnergy = Float(abs(slope)) * Float(points.count)

        let obs = RSFrameProbeObservation(
            rowSlope: Float(slope),
            nonUniformity: Float(variance),
            edgeEnergy: edgeEnergy,
            valid: abs(slope) > 0.0005
        )

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x10,
            valueA: obs.rowSlope,
            valueB: obs.edgeEnergy
        )

        return obs
    }
}
