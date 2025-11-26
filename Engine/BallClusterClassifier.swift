// File: Vision/BallLock/BallClusterClassifier.swift
// BallClusterClassifier -- classifies LK-refined dots inside an ROI into a ball cluster.
// Uses normalized CNT/SYM/RAD, eccentricity, and research-weighted quality.

import Foundation
import CoreGraphics

struct BallClusterParams {
    let minCorners: Int
    let maxCorners: Int
    let minRadiusPx: CGFloat
    let maxRadiusPx: CGFloat
    let idealRadiusMinPx: CGFloat
    let idealRadiusMaxPx: CGFloat
    let roiBorderMarginPx: CGFloat

    /// Weighting + shaping
    let symmetryWeight: CGFloat   // ~0.4
    let countWeight: CGFloat      // ~0.4
    let radiusWeight: CGFloat     // ~0.2

    static let `default` = BallClusterParams(
        minCorners: 8,
        maxCorners: 28,
        minRadiusPx: 10,
        maxRadiusPx: 120,
        idealRadiusMinPx: 20,
        idealRadiusMaxPx: 60,
        roiBorderMarginPx: 10,
        symmetryWeight: 0.40,
        countWeight: 0.40,
        radiusWeight: 0.20
    )
}

struct BallCluster {
    let centroid: CGPoint
    let radiusPx: CGFloat
    let count: Int

    /// Normalized scores in [0, 1] after research mapping:
    ///   CNT:  8 → 0, 20 → 1
    ///   SYM:  0.50 → 0, 0.90 → 1
    ///   RAD:  10 → 0, 50 → 1
    let symmetryScore: CGFloat
    let countScore: CGFloat
    let radiusScore: CGFloat

    /// Shape eccentricity = majorAxis / minorAxis
    /// (must be < 2.0 for a valid ball cluster)
    let eccentricity: CGFloat

    /// Composite quality in [0, 1] using weights:
    ///   Q = wCount * CNT + wSym * SYM + wRad * RAD
    let qualityScore: CGFloat
}

final class BallClusterClassifier {

    /// Classifies refined LK dots into a single ball cluster inside the given ROI.
    ///
    /// - Parameters:
    ///   - dots: Refined LK dots (positions only, in pixel coords).
    ///   - imageSize: Image size (currently unused).
    ///   - roiCenter: ROI center in pixel coordinates.
    ///   - roiRadius: ROI radius in pixels.
    ///   - params: Ball cluster tuning parameters.
    ///
    /// - Returns: BallCluster if a valid ball-like cluster is found, otherwise nil.
    func classify(
        dots: [CGPoint],
        imageSize: CGSize,
        roiCenter: CGPoint,
        roiRadius: CGFloat,
        params: BallClusterParams
    ) -> BallCluster? {
        _ = imageSize // reserved for future use

        if dots.isEmpty {
            return nil
        }

        let roiRadiusSq = roiRadius * roiRadius

        // --------------------------------------------------------
        // 1) Gather points INSIDE ROI + centroid
        // --------------------------------------------------------
        var insidePoints: [CGPoint] = []
        insidePoints.reserveCapacity(dots.count)

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for dot in dots {
            let dx = dot.x - roiCenter.x
            let dy = dot.y - roiCenter.y
            let distSq = dx * dx + dy * dy
            if distSq <= roiRadiusSq {
                insidePoints.append(dot)
                sumX += dot.x
                sumY += dot.y
            }
        }

        let insideCount = insidePoints.count

        // Hard cap: minimum number of dots inside ROI.
        if insideCount < 5 {
            return nil
        }

        // Global count gating
        if insideCount < params.minCorners || insideCount > params.maxCorners {
            return nil
        }

        let invCount = 1.0 / CGFloat(insideCount)
        let centroid = CGPoint(x: sumX * invCount, y: sumY * invCount)

        // --------------------------------------------------------
        // 2) Radius, symmetry, covariance for eccentricity
        // --------------------------------------------------------
        var maxRadius: CGFloat = 0

        // symmetry: mean unit vector magnitude
        var sumUnitX: CGFloat = 0
        var sumUnitY: CGFloat = 0

        // covariance accumulators (about centroid)
        var sumXX: CGFloat = 0
        var sumXY: CGFloat = 0
        var sumYY: CGFloat = 0

        for dot in insidePoints {
            let dx = dot.x - centroid.x
            let dy = dot.y - centroid.y
            let r = sqrt(dx * dx + dy * dy)

            if r > maxRadius {
                maxRadius = r
            }

            if r > 1e-3 {
                sumUnitX += dx / r
                sumUnitY += dy / r
            }

            sumXX += dx * dx
            sumXY += dx * dy
            sumYY += dy * dy
        }

        // Radius hard bounds
        if maxRadius < params.minRadiusPx || maxRadius > params.maxRadiusPx {
            return nil
        }

        // Edge-of-ROI rejection: centroid must be at least margin away from ROI boundary.
        let dxC = centroid.x - roiCenter.x
        let dyC = centroid.y - roiCenter.y
        let distCentroidToRoiCenter = sqrt(dxC * dxC + dyC * dyC)
        if roiRadius - distCentroidToRoiCenter < params.roiBorderMarginPx {
            return nil
        }

        // --------------------------------------------------------
        // Symmetry score (raw) -- 1 = perfect radial, 0 = bad
        // --------------------------------------------------------
        let rawSymmetry: CGFloat
        if insideCount > 0 {
            let invInside = 1.0 / CGFloat(insideCount)
            let meanUnitX = sumUnitX * invInside
            let meanUnitY = sumUnitY * invInside
            let meanLen = sqrt(meanUnitX * meanUnitX + meanUnitY * meanUnitY)

            // simple radial-ness: small meanLen → better symmetry
            let raw = 1.0 - meanLen
            rawSymmetry = max(0, min(raw, 1))
        } else {
            rawSymmetry = 0
        }

        // Research: reject symmetry < 0.50 outright
        if rawSymmetry < 0.50 {
            return nil
        }

        // --------------------------------------------------------
        // 3) Eccentricity from covariance (PCA on cluster points)
        // --------------------------------------------------------
        let covScale = invCount
        let a = sumXX * covScale
        let b = sumXY * covScale
        let c = sumYY * covScale

        // Eigenvalues of 2x2 symmetric matrix [[a, b], [b, c]]
        let trace = a + c
        let det = a * c - b * b
        let discriminant = max(0, trace * trace - 4 * det)
        let root = sqrt(discriminant)

        let lambda1 = 0.5 * (trace + root)
        let lambda2 = 0.5 * (trace - root)

        let maxLambda = max(lambda1, lambda2)
        let minLambda = min(lambda1, lambda2)

        // If cluster is almost line-like or degenerate → reject
        if minLambda <= 1e-6 {
            return nil
        }

        let eccentricity = maxLambda / minLambda
        // Research: ball cluster must be < 2:1 major/minor axis
        if eccentricity >= 2.0 {
            return nil
        }

        // --------------------------------------------------------
        // 4) Research-normalized scores (0–1)
        //
        // CNT: 8  → 0, 20 → 1
        // SYM: 0.50 → 0, 0.90 → 1
        // RAD: 10 → 0, 50 → 1
        // --------------------------------------------------------

        func norm(_ x: CGFloat, _ x0: CGFloat, _ x1: CGFloat) -> CGFloat {
            guard x1 > x0 else { return 0 }
            let t = (x - x0) / (x1 - x0)
            return max(0, min(t, 1))
        }

        let countScore = norm(CGFloat(insideCount), 8.0, 20.0)
        let symmetryScore = norm(rawSymmetry, 0.50, 0.90)
        let radiusScore = norm(maxRadius, 10.0, 50.0)

        // --------------------------------------------------------
        // 5) Composite quality with weights (0.4 CNT, 0.4 SYM, 0.2 RAD)
        // --------------------------------------------------------
        let wCount = params.countWeight
        let wSym   = params.symmetryWeight
        let wRad   = params.radiusWeight

        var qualityScore =
            wCount * countScore +
            wSym   * symmetryScore +
            wRad   * radiusScore

        qualityScore = max(0, min(qualityScore, 1))

        if qualityScore <= 0 {
            return nil
        }

        return BallCluster(
            centroid: centroid,
            radiusPx: maxRadius,
            count: insideCount,
            symmetryScore: symmetryScore,
            countScore: countScore,
            radiusScore: radiusScore,
            eccentricity: eccentricity,
            qualityScore: qualityScore
        )
    }
}