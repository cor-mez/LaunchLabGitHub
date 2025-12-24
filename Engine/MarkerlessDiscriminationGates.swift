//
//  MarkerlessDiscriminationGates.swift
//  Engine
//
//  Markerless Discrimination Gates (MDG)
//  Phase: Detection Hardening (Pre-Pose)
//  - Does NOT modify BallLock
//  - Does NOT touch RS-Window validity
//  - Does NOT emit or consume pose
//  - Deterministic, refusal-first
//

import Foundation
import CoreGraphics

final class MarkerlessDiscriminationGates {

    // MARK: - Output

    struct Decision: Equatable {
        let ballLikeEvidence: Bool
        let reason: String?               // nil when accepted

        let compactness: Double           // MAD(dist)/median(dist)
        let anisotropy: Double            // λ1/λ2 (PCA)
        let radiusMadRatio: Double?       // MAD(radius)/median(radius) across history (optional)

        let vPxPerSec: Double?            // motion magnitude (optional)
        let staticSuspiciousFrames: Int   // consecutive suspicious-static frames
    }

    // MARK: - Config (fixed constants; not UI knobs)

    struct Config: Equatable {
        // Geometric gate
        var anisotropyReject: Double = 6.0
        var anisotropySuspicious: Double = 3.5
        var compactnessReject: Double = 0.42

        // Radius stability (across frames)
        var radiusHistory: Int = 6
        var radiusMadRatioReject: Double = 0.25

        // Motion plausibility (secondary)
        var staticVelocityPxPerSec: Double = 1.0
        var staticFramesToReject: Int = 30
        var teleportFactorRadius: Double = 2.5

        // Logging
        var logTransitionsOnly: Bool = true
        var summaryEveryNEvals: Int = 120
    }

    // MARK: - State

    private var cfg: Config
    private var evalCount: Int = 0

    private var acceptCount: Int = 0
    private var geomRejectCount: Int = 0
    private var motionRejectCount: Int = 0

    private var radii = RingBuffer<Double>(capacity: 6)

    private var lastCenter: CGPoint? = nil
    private var lastTimeSec: Double? = nil
    private var staticSuspiciousFrames: Int = 0

    private var lastLogKeyGeom: String? = nil
    private var lastLogKeyMotion: String? = nil

    init(config: Config = Config()) {
        self.cfg = config
        self.radii = RingBuffer<Double>(capacity: config.radiusHistory)
    }

    // MARK: - Evaluate

    func evaluate(points: [CGPoint],
                  candidateCenter: CGPoint,
                  candidateRadiusPx: CGFloat,
                  timestampSec: Double) -> Decision {

        evalCount += 1

        // --- radius history (observational) ---
        if candidateRadiusPx.isFinite && candidateRadiusPx > 0 {
            radii.push(Double(candidateRadiusPx))
        }
        let radiusMadRatio = radii.madRatio()

        // --- geom metrics ---
        let anisotropy = pcaAnisotropy(points: points)
        let compactness = radialCompactness(points: points, center: candidateCenter)

        // --- geom decision ---
        var ballLike = true
        var reason: String? = nil

        if points.count < 6 {
            ballLike = false
            reason = "few_points"
        } else if anisotropy >= cfg.anisotropyReject {
            ballLike = false
            reason = "edge_like_anisotropy"
        } else if anisotropy >= cfg.anisotropySuspicious && compactness >= cfg.compactnessReject {
            ballLike = false
            reason = "edge_like_compactness"
        } else if let r = radiusMadRatio, r >= cfg.radiusMadRatioReject {
            ballLike = false
            reason = "radius_unstable"
        }

        // log geom (transition-only by default)
        logGeomIfNeeded(ballLike: ballLike,
                        reason: reason,
                        compactness: compactness,
                        anisotropy: anisotropy)

        // --- motion metrics (computed regardless; gating only if geom passed) ---
        let (vPxPerSec, jumpPx) = motion(center: candidateCenter, nowSec: timestampSec)

        // Update suspicious-static counter (only when geom looks suspicious-ish)
        if let v = vPxPerSec,
           v < cfg.staticVelocityPxPerSec,
           anisotropy >= cfg.anisotropySuspicious {
            staticSuspiciousFrames += 1
        } else {
            staticSuspiciousFrames = 0
        }

        if ballLike {
            // Teleport check only when geometry is not strongly ball-like
            if let jump = jumpPx,
               candidateRadiusPx.isFinite, candidateRadiusPx > 0,
               jump > cfg.teleportFactorRadius * Double(candidateRadiusPx),
               anisotropy >= cfg.anisotropySuspicious {
                ballLike = false
                reason = "teleport/discontinuity"
            } else if staticSuspiciousFrames >= cfg.staticFramesToReject {
                ballLike = false
                reason = "static/background_candidate"
            }
        }

        logMotionIfNeeded(ballLike: ballLike,
                          reason: reason,
                          vPxPerSec: vPxPerSec)

        // Counters (for boring summaries)
        if ballLike {
            acceptCount += 1
        } else {
            // classify as geom vs motion reject
            if reason == "few_points" ||
                reason == "edge_like_anisotropy" ||
                reason == "edge_like_compactness" ||
                reason == "radius_unstable" {
                geomRejectCount += 1
            } else {
                motionRejectCount += 1
            }
        }

        if DebugProbe.isEnabled(.capture),
           cfg.summaryEveryNEvals > 0,
           (evalCount % cfg.summaryEveryNEvals) == 0 {
            Log.info(.detection, "MDG SUMMARY eval=\(evalCount) accept=\(acceptCount) geomReject=\(geomRejectCount) motionReject=\(motionRejectCount)")
        }

        // Update motion history
        lastCenter = candidateCenter
        lastTimeSec = timestampSec

        return Decision(
            ballLikeEvidence: ballLike,
            reason: ballLike ? nil : reason,
            compactness: compactness,
            anisotropy: anisotropy,
            radiusMadRatio: radiusMadRatio,
            vPxPerSec: vPxPerSec,
            staticSuspiciousFrames: staticSuspiciousFrames
        )
    }

    // MARK: - Gate 1 helpers (Geometry)

    /// PCA anisotropy = λ1/λ2 on 2x2 covariance. Large => line-like.
    private func pcaAnisotropy(points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        var mx: Double = 0
        var my: Double = 0
        let n = Double(points.count)

        for p in points {
            mx += Double(p.x)
            my += Double(p.y)
        }
        mx /= n
        my /= n

        var a: Double = 0  // varX
        var b: Double = 0  // covXY
        var c: Double = 0  // varY

        for p in points {
            let dx = Double(p.x) - mx
            let dy = Double(p.y) - my
            a += dx * dx
            b += dx * dy
            c += dy * dy
        }
        a /= n
        b /= n
        c /= n

        let trace = a + c
        let disc = sqrt(max(0, (a - c) * (a - c) + 4 * b * b))
        let l1 = (trace + disc) * 0.5
        let l2 = (trace - disc) * 0.5

        let eps = 1e-9
        return (l1 + eps) / (l2 + eps)
    }

    /// Radial compactness = MAD(dist)/median(dist). Higher => more line-like / spready.
    private func radialCompactness(points: [CGPoint], center: CGPoint) -> Double {
        guard !points.isEmpty else { return 1 }

        var ds: [Double] = []
        ds.reserveCapacity(points.count)

        for p in points {
            let dx = Double(p.x - center.x)
            let dy = Double(p.y - center.y)
            ds.append(sqrt(dx*dx + dy*dy))
        }

        let med = median(ds)
        let mad = median(ds.map { abs($0 - med) })
        let eps = 1e-9
        return mad / (med + eps)
    }

    // MARK: - Gate 2 helpers (Motion)

    private func motion(center: CGPoint, nowSec: Double) -> (vPxPerSec: Double?, jumpPx: Double?) {
        guard let prev = lastCenter, let prevT = lastTimeSec else {
            return (nil, nil)
        }
        let dt = nowSec - prevT
        guard dt > 1e-6 else { return (nil, nil) }

        let dx = Double(center.x - prev.x)
        let dy = Double(center.y - prev.y)
        let jump = sqrt(dx*dx + dy*dy)
        return (jump / dt, jump)
    }

    // MARK: - Logging (boring, transition-only)

    private func logGeomIfNeeded(ballLike: Bool, reason: String?, compactness: Double, anisotropy: Double) {
        guard DebugProbe.isEnabled(.capture) else { return }

        let key = "\(ballLike ? "A" : "R")|\(reason ?? "ok")|\(String(format: "%.3f", compactness))|\(String(format: "%.2f", anisotropy))"
        if cfg.logTransitionsOnly, key == lastLogKeyGeom { return }
        lastLogKeyGeom = key

        if ballLike {
            Log.info(.detection, "MDG GEOM accept compactness=\(compactness) anisotropy=\(anisotropy)")
        } else {
            Log.info(.detection, "MDG GEOM reject anisotropy=\(anisotropy) compactness=\(compactness) reason=\(reason ?? "unknown")")
        }
    }

    private func logMotionIfNeeded(ballLike: Bool, reason: String?, vPxPerSec: Double?) {
        guard DebugProbe.isEnabled(.capture) else { return }

        let vStr = vPxPerSec.map { String(format: "%.2f", $0) } ?? "n/a"
        let key = "\(ballLike ? "A" : "R")|\(reason ?? "ok")|\(vStr)|static=\(staticSuspiciousFrames)"
        if cfg.logTransitionsOnly, key == lastLogKeyMotion { return }
        lastLogKeyMotion = key

        if ballLike {
            Log.info(.detection, "MDG MOTION accept v=\(vStr) px/s")
        } else if reason == "static/background_candidate" {
            Log.info(.detection, "MDG MOTION reject static v=\(vStr) px/s")
        } else if reason == "teleport/discontinuity" {
            Log.info(.detection, "MDG MOTION reject teleport v=\(vStr) px/s")
        }
    }

    // MARK: - Small stats helpers

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        if s.count % 2 == 0 {
            return 0.5 * (s[mid - 1] + s[mid])
        } else {
            return s[mid]
        }
    }

    fileprivate struct RingBuffer<T> {
        fileprivate(set) var values: [T] = []
        private let capacity: Int

        init(capacity: Int) {
            self.capacity = max(1, capacity)
            self.values.reserveCapacity(self.capacity)
        }

        mutating func push(_ v: T) {
            values.append(v)
            if values.count > capacity {
                values.removeFirst(values.count - capacity)
            }
        }
    }
}

private extension MarkerlessDiscriminationGates.RingBuffer where T == Double {
    func madRatio(minN: Int = 6) -> Double? {
        guard values.count >= minN else { return nil }
        let s = values.sorted()
        let med: Double = {
            let mid = s.count / 2
            if s.count % 2 == 0 { return 0.5 * (s[mid - 1] + s[mid]) }
            return s[mid]
        }()
        let dev = s.map { abs($0 - med) }.sorted()
        let mad: Double = {
            let mid = dev.count / 2
            if dev.count % 2 == 0 { return 0.5 * (dev[mid - 1] + dev[mid]) }
            return dev[mid]
        }()
        let eps = 1e-9
        return mad / (med + eps)
    }
}
