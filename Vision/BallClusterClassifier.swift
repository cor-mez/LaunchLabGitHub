// File: Vision/BallLock/BallClusterClassifier.swift
// BallClusterClassifier — classifies LK-refined dots inside an ROI into a ball cluster.
// Uses only VisionTypes.swift shared types via VisionPipeline; no global model changes.

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
    let symmetryScale: CGFloat
    let symmetryWeight: CGFloat
    let countWeight: CGFloat
    let radiusWeight: CGFloat

    static let `default` = BallClusterParams(
        minCorners: 8,
        maxCorners: 28,
        minRadiusPx: 10,
        maxRadiusPx: 120,
        idealRadiusMinPx: 20,
        idealRadiusMaxPx: 60,
        roiBorderMarginPx: 10,
        symmetryScale: 1.5,
        symmetryWeight: 0.40,
        countWeight: 0.40,
        radiusWeight: 0.20
    )
}

struct BallCluster {
    let centroid: CGPoint
    let radiusPx: CGFloat
    let count: Int
    let symmetryScore: CGFloat
    let countScore: CGFloat
    let radiusScore: CGFloat
    let qualityScore: CGFloat
    let eccentricity: CGFloat
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
        // 1) Centroid over dots strictly inside ROI
        // --------------------------------------------------------
        var insidePoints: [CGPoint] = []
        insidePoints.reserveCapacity(dots.count)

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var insideCount = 0

        for dot in dots {
            let dx = dot.x - roiCenter.x
            let dy = dot.y - roiCenter.y
            let distSq = dx * dx + dy * dy
            if distSq <= roiRadiusSq {
                sumX += dot.x
                sumY += dot.y
                insideCount += 1
                insidePoints.append(dot)
            }
        }

        // Hard cap: minimum number of dots inside ROI.
        if insideCount < 5 {
            return nil
        }

        if insideCount < params.minCorners || insideCount > params.maxCorners {
            return nil
        }

        let invCount = 1.0 / CGFloat(insideCount)
        let centroid = CGPoint(x: sumX * invCount, y: sumY * invCount)

        // --------------------------------------------------------
        // 2) Radius + raw symmetry score
        // --------------------------------------------------------
        var maxRadius: CGFloat = 0
        var sumUnitX: CGFloat = 0
        var sumUnitY: CGFloat = 0

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
        }

        // Radius hard bounds.
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

        // Raw symmetry: for a circular cluster, mean unit vector magnitude should be small.
        var rawSymmetry: CGFloat = 0
        if insideCount > 0 {
            let invInside = 1.0 / CGFloat(insideCount)
            let meanUnitX = sumUnitX * invInside
            let meanUnitY = sumUnitY * invInside
            let meanLen = sqrt(meanUnitX * meanUnitX + meanUnitY * meanUnitY)
            let raw = 1.0 - meanLen * params.symmetryScale
            rawSymmetry = max(0, min(1, raw))
        }

        // Research: reject raw symmetry < 0.50 outright.
        if rawSymmetry < 0.50 {
            return nil
        }

        // Normalized symmetry score: 0.50 → 0, 0.90 → 1.
        let symmetryScore: CGFloat
        let symLo: CGFloat = 0.50
        let symHi: CGFloat = 0.90
        if rawSymmetry <= symLo {
            symmetryScore = 0
        } else if rawSymmetry >= symHi {
            symmetryScore = 1
        } else {
            symmetryScore = (rawSymmetry - symLo) / (symHi - symLo)
        }

        // --------------------------------------------------------
        // 3) Count score (0–1), CNT: 8 → 0, 20 → 1
        // --------------------------------------------------------
        let c = CGFloat(insideCount)
        let cntLo: CGFloat = 8.0
        let cntHi: CGFloat = 20.0
        let countScore: CGFloat
        if c <= cntLo {
            countScore = 0
        } else if c >= cntHi {
            countScore = 1
        } else {
            countScore = (c - cntLo) / (cntHi - cntLo)
        }

        // --------------------------------------------------------
        // 4) Radius score RAD: 10 → 0, 50 → 1
        // --------------------------------------------------------
        let r = maxRadius
        let radLo: CGFloat = 10.0
        let radHi: CGFloat = 50.0
        let radiusScore: CGFloat
        if r <= radLo {
            radiusScore = 0
        } else if r >= radHi {
            radiusScore = 1
        } else {
            radiusScore = (r - radLo) / (radHi - radLo)
        }

        // --------------------------------------------------------
        // 5) Eccentricity via covariance PCA (major/minor axis).
        //     Reject clusters with major/minor >= 2.0
        // --------------------------------------------------------
        var eccentricity: CGFloat = 1.0

        if insidePoints.count >= 3 {
            var sxx: CGFloat = 0
            var sxy: CGFloat = 0
            var syy: CGFloat = 0
            let n = CGFloat(insidePoints.count)

            for p in insidePoints {
                let dx = p.x - centroid.x
                let dy = p.y - centroid.y
                sxx += dx * dx
                sxy += dx * dy
                syy += dy * dy
            }

            sxx /= n
            sxy /= n
            syy /= n

            let trace = sxx + syy
            let halfTrace = trace * 0.5
            let det = sxx * syy - sxy * sxy
            let disc = max(halfTrace * halfTrace - det, 0)
            let root = sqrt(disc)

            var lambda1 = halfTrace + root
            var lambda2 = halfTrace - root
            lambda1 = max(lambda1, 0)
            lambda2 = max(lambda2, 0)

            let majorVar = max(lambda1, lambda2)
            let minorVar = min(lambda1, lambda2)
            let minorSafe = max(minorVar, 1e-6)

            eccentricity = sqrt(majorVar / minorSafe)
        }

        if eccentricity >= 2.0 {
            // Too elongated to be a ball.
            return nil
        }

        // --------------------------------------------------------
        // 6) Final quality: weighted blend of scores.
        //    Defaults: 0.4 count, 0.4 symmetry, 0.2 radius.
        //    We renormalize weights from params to sum to 1.
        // --------------------------------------------------------
        var wCount = params.countWeight
        var wSym   = params.symmetryWeight
        var wRad   = params.radiusWeight

        let wSum = wCount + wSym + wRad
        if wSum > 1e-6 {
            wCount /= wSum
            wSym   /= wSum
            wRad   /= wSum
        } else {
            // Fallback to research defaults
            wCount = 0.4
            wSym   = 0.4
            wRad   = 0.2
        }

        var qualityScore =
            wCount * countScore +
            wSym   * symmetryScore +
            wRad   * radiusScore

        qualityScore = max(0, min(1, qualityScore))

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
            qualityScore: qualityScore,
            eccentricity: eccentricity
        )
    }
}
