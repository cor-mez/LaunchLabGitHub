// File: Vision/RS/RSDegeneracyMetrics.swift
// Lightweight RS-degeneracy scoring module.
// Uses only existing VisionTypes.swift data (no new model types).

import Foundation
import CoreGraphics
import simd

// ------------------------------------------------------------
// MARK: - Result Types
// ------------------------------------------------------------

struct RSDegeneracyMetrics {
    let rowSpan: CGFloat
    let shearSlope: CGFloat
    let blurStreak: CGFloat
    let patternPhaseRatio: CGFloat

    let hasCriticalDegeneracy: Bool
    let nonCriticalCount: Int
}

struct RSConfidenceResult {
    let metrics: RSDegeneracyMetrics
    let confidence: CGFloat   // 0.0 – 1.0
}

// ------------------------------------------------------------
// MARK: - RSDegeneracyCalculator
// ------------------------------------------------------------

final class RSDegeneracyCalculator {

    // Tunable thresholds (match research corridor)
    private let minRowSpan: CGFloat = 18.0
    private let shearThreshold: CGFloat = 0.004
    private let blurNonCrit: CGFloat = 2.8
    private let blurCrit: CGFloat = 5.0
    private let phaseAlias: CGFloat = 1.6
    private let centerRadius: CGFloat = 25.0
    private let centerCritRowSpan: CGFloat = 25.0

    init() {}

    // --------------------------------------------------------
    // MARK: Public API
    // --------------------------------------------------------
    func computeMetrics(
        clusterDots: [CGPoint],
        centroid: CGPoint?,
        principalPoint: CGPoint
    ) -> RSDegeneracyMetrics {

        guard clusterDots.count >= 3 else {
            return RSDegeneracyMetrics(
                rowSpan: 0,
                shearSlope: 0,
                blurStreak: 0,
                patternPhaseRatio: 0,
                hasCriticalDegeneracy: true,
                nonCriticalCount: 0
            )
        }

        // --------------------------------------------------------
        // 1) Row-span (minY/maxY)
        // --------------------------------------------------------
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = CGFloat.leastNormalMagnitude
        for p in clusterDots {
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        let rowSpan = maxY - minY

        // --------------------------------------------------------
        // 2) Shear: least-squares slope dx/dy
        // --------------------------------------------------------
        var sumY: CGFloat = 0
        var sumYY: CGFloat = 0
        var sumXY: CGFloat = 0
        let n = CGFloat(clusterDots.count)

        for p in clusterDots {
            let y = p.y
            sumY += y
            sumYY += y*y
        }
        let meanY = sumY / n

        for p in clusterDots {
            let dy = p.y - meanY
            sumXY += (p.x * (p.y - meanY))
        }

        let denom = max(sumYY - n*meanY*meanY, 1e-6)
        let shearSlope = sumXY / denom   // dx/dy

        // --------------------------------------------------------
        // 3) Blur / streak proxy
        // Just a placeholder metric for now:
        //   blurStreak ~ average |dx| or |dy| across cluster.
        // --------------------------------------------------------
        var accumBlur: CGFloat = 0
        for i in 0..<clusterDots.count-1 {
            let p0 = clusterDots[i]
            let p1 = clusterDots[i+1]
            let dx = abs(p1.x - p0.x)
            let dy = abs(p1.y - p0.y)
            accumBlur += max(dx, dy)
        }
        let blurStreak = accumBlur / CGFloat(max(clusterDots.count - 1, 1))

        // --------------------------------------------------------
        // 4) Pattern-phase / alias stub
        // Later replaced by RS-corrected dot alignment.
        // --------------------------------------------------------
        let patternPhaseRatio: CGFloat = (blurStreak > 0.1) ? 1.0 : 0.5

        // --------------------------------------------------------
        // 5) Critical / non-critical checks
        // --------------------------------------------------------
        var hasCritical = false
        var nonCrit = 0

        // row-span tiny → critical
        if rowSpan < minRowSpan {
            hasCritical = true
        }

        // shear tiny → critical
        if abs(shearSlope) < shearThreshold {
            hasCritical = true
        }

        // strong alias
        if patternPhaseRatio > phaseAlias {
            hasCritical = true
        }

        // strong blur
        if blurStreak > blurCrit {
            hasCritical = true
        }

        // central ambiguity
        if let c = centroid {
            let dx = c.x - principalPoint.x
            let dy = c.y - principalPoint.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist <= centerRadius && rowSpan < centerCritRowSpan {
                hasCritical = true
            }
        }

        // non-critical degradations
        if blurStreak > blurNonCrit { nonCrit += 1 }
        if patternPhaseRatio > 1.2   { nonCrit += 1 }
        if rowSpan < 30              { nonCrit += 1 }

        return RSDegeneracyMetrics(
            rowSpan: rowSpan,
            shearSlope: shearSlope,
            blurStreak: blurStreak,
            patternPhaseRatio: patternPhaseRatio,
            hasCriticalDegeneracy: hasCritical,
            nonCriticalCount: nonCrit
        )
    }

    // --------------------------------------------------------
    // MARK: Confidence model
    // --------------------------------------------------------
    func computeConfidence(from metrics: RSDegeneracyMetrics) -> RSConfidenceResult {

        if metrics.hasCriticalDegeneracy {
            return RSConfidenceResult(
                metrics: metrics,
                confidence: 0.0
            )
        }

        var c: CGFloat = 1.0

        // subtract per non-critical
        c -= 0.18 * CGFloat(metrics.nonCriticalCount)

        // clamp
        c = max(0, min(c, 1))

        return RSConfidenceResult(metrics: metrics, confidence: c)
    }
}