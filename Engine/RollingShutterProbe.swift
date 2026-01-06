//
//  RollingShutterProbe.swift
//  LaunchLab
//
//  Pure measurement of rolling-shutter observables.
//  NO detection, NO authority, NO thresholds.
//

import CoreGraphics
import Accelerate

struct RSProbeResult {
    let rowSlope: Double
    let rowSlopeR2: Double
    let rowNonuniformity: Double
    let streakLength: Double
    let streakWidth: Double
    let streakLW: Double
    let edgeStraightness: Double
}

final class RollingShutterProbe {

    func evaluate(points: [CGPoint], roi: CGRect) -> RSProbeResult? {
        guard points.count >= 12 else { return nil }

        let h = Int(roi.height)
        var rowEnergy = [Double](repeating: 0, count: h)

        // --------------------------------------------------
        // 1. Row-wise energy accumulation
        // --------------------------------------------------
        for p in points {
            let ry = Int(p.y)
            guard ry >= 0 && ry < h else { continue }
            rowEnergy[ry] += 1.0
        }

        let mean = rowEnergy.reduce(0, +) / Double(h)
        guard mean > 0 else { return nil }

        // --------------------------------------------------
        // 2. Linear slope fit (least squares)
        // --------------------------------------------------
        let ys = (0..<h).map { Double($0) }
        let xs = rowEnergy

        let xMean = xs.reduce(0, +) / Double(h)
        let yMean = ys.reduce(0, +) / Double(h)

        var num = 0.0
        var den = 0.0
        for i in 0..<h {
            num += (ys[i] - yMean) * (xs[i] - xMean)
            den += (ys[i] - yMean) * (ys[i] - yMean)
        }

        let slope = den > 0 ? num / den : 0

        // R²
        var ssTot = 0.0
        var ssRes = 0.0
        for i in 0..<h {
            let fit = slope * (ys[i] - yMean) + xMean
            ssTot += pow(xs[i] - xMean, 2)
            ssRes += pow(xs[i] - fit, 2)
        }
        let r2 = ssTot > 0 ? 1.0 - (ssRes / ssTot) : 0

        // --------------------------------------------------
        // 3. Non-uniformity
        // --------------------------------------------------
        let variance = xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(h)
        let nonuniformity = sqrt(variance) / mean

        // --------------------------------------------------
        // 4. Streak geometry (PCA)
        // --------------------------------------------------
        let cx = points.map { Double($0.x) }.reduce(0, +) / Double(points.count)
        let cy = points.map { Double($0.y) }.reduce(0, +) / Double(points.count)

        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = Double(p.x) - cx
            let dy = Double(p.y) - cy
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        let trace = sxx + syy
        let det = sxx * syy - sxy * sxy
        let disc = sqrt(max(0, trace * trace / 4 - det))

        let lambda1 = trace / 2 + disc
        let lambda2 = trace / 2 - disc

        let length = sqrt(max(lambda1, 1e-6))
        let width  = sqrt(max(lambda2, 1e-6))
        let lw = length / max(width, 1e-6)

        // --------------------------------------------------
        // 5. Static edge straightness
        // --------------------------------------------------
        let straightness = lw > 1 ? min(1.0, lw / 20.0) : 0.0

        return RSProbeResult(
            rowSlope: slope,
            rowSlopeR2: r2,
            rowNonuniformity: nonuniformity,
            streakLength: length,
            streakWidth: width,
            streakLW: lw,
            edgeStraightness: straightness
        )
    }
}
