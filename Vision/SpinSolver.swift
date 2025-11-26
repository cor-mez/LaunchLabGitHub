//
//  SpinSolver.swift
//  LaunchLab
//
//  Spin V1  (Natural Texture Spin Estimator)
//  Frozen-contract compliant: outputs full SpinResult
//
//  Strategy:
//   • compensate LK flows for forward translation (from RS-PnP v)
//   • derive tangential flow around ROI centroid
//   • solve dominant rotational axis via PCA on r × v_rot
//   • compute angular velocity ω from tangential speed
//

import Foundation
import simd
import CoreGraphics

public final class SpinSolver {

    private let ballRadius: Float = 0.021335    // meters
    private let fps: Float = 240.0
    private let dt: Float = 1.0 / 240.0

    public init() {}

    // ---------------------------------------------------------------------
    // MARK: - Public Entry Point
    // ---------------------------------------------------------------------

    public func solve(
        window: RSWindow,
        pnp: RSPnPResult,
        intrinsics: CameraIntrinsics,
        flows: [SIMD2<Float>]
    ) -> SpinResult? {

        let frames = window.frames
        guard frames.count == 3 else { return nil }

        let dots = frames[2].dots
        if dots.isEmpty || flows.isEmpty { return nil }

        // 1. Compute ball centroid
        guard let centroid = computeCentroid(dots) else { return nil }

        // 2. Build rotational flow samples (remove translation)
        let samples = computeRotationalFlow(
            dots: dots,
            flows: flows,
            centroid: centroid,
            v: pnp.v               // translational velocity from SE3
        )

        if samples.count < 4 { return nil }

        // 3. Solve rotation axis from cross products
        let axis = estimateAxis(from: samples)
        if simd_length(axis) < 1e-6 { return nil }

        // 4. Solve angular magnitude from tangential speeds
        guard let omega = estimateOmega(
            samples: samples,
            depth: pnp.t.z,
            intrinsics: intrinsics
        ) else { return nil }

        // 5. Package frozen SpinResult
        let rpm = omega * 60.0 / (2.0 * .pi)

        let confidence: Float = {
            let n = Float(samples.count)
            if n < 4 { return 0 }
            if n >= 20 { return 1 }
            return min(1, n / 20)
        }()

        return SpinResult(
            omega: SIMD3<Float>(0, 0, omega),   // V1: rotation around axis approx
            rpm: rpm,
            axis: simd_normalize(axis),
            confidence: confidence
        )
    }

    // ---------------------------------------------------------------------
    // MARK: - Centroid
    // ---------------------------------------------------------------------

    private func computeCentroid(_ dots: [VisionDot]) -> CGPoint? {
        guard !dots.isEmpty else { return nil }
        var sx: CGFloat = 0, sy: CGFloat = 0
        let n = CGFloat(dots.count)
        for d in dots {
            sx += d.position.x
            sy += d.position.y
        }
        return CGPoint(x: sx/n, y: sy/n)
    }

    // ---------------------------------------------------------------------
    // MARK: - Translational Compensation
    // ---------------------------------------------------------------------

    private func computeRotationalFlow(
        dots: [VisionDot],
        flows: [SIMD2<Float>],
        centroid: CGPoint,
        v: SIMD3<Float>
    ) -> [(CGPoint, SIMD2<Float>)] {

        let v2d = SIMD2<Float>(v.x, v.y)

        var out: [(CGPoint, SIMD2<Float>)] = []
        out.reserveCapacity(dots.count)

        for i in 0..<min(dots.count, flows.count) {

            let p = dots[i].position
            let flow = flows[i]

            let dx = Float(p.x - centroid.x)
            let dy = Float(p.y - centroid.y)
            let r = SIMD2<Float>(dx, dy)
            if simd_length(r) < 1e-3 { continue }

            // Project translational flow onto pixel plane
            let proj = simd_dot(flow, v2d) / (simd_length_squared(v2d) + 1e-6)
            let translationalComponent = proj * v2d

            let rotationalComponent = flow - translationalComponent
            out.append((p, rotationalComponent))
        }

        return out
    }

    // ---------------------------------------------------------------------
    // MARK: - Axis Solve
    // ---------------------------------------------------------------------

    /// dominant axis from PCA-like cross vector sum
    private func estimateAxis(from samples: [(CGPoint, SIMD2<Float>)]) -> SIMD3<Float> {

        var acc = SIMD3<Float>(0,0,0)

        for (p, f) in samples {
            let r = SIMD3<Float>(Float(p.x), Float(p.y), 0)
            let f3 = SIMD3<Float>(f.x, f.y, 0)
            acc += simd_cross(r, f3)
        }

        if simd_length(acc) < 1e-6 { return SIMD3<Float>(0,0,0) }
        return simd_normalize(acc)
    }

    // ---------------------------------------------------------------------
    // MARK: - Angular Velocity Magnitude
    // ---------------------------------------------------------------------

    private func estimateOmega(
        samples: [(CGPoint, SIMD2<Float>)],
        depth: Float,
        intrinsics: CameraIntrinsics
    ) -> Float? {

        let fx = intrinsics.fx
        var totalTangentialPx: Float = 0
        var count: Float = 0

        for (_, f) in samples {
            let mag = simd_length(f)
            if mag < 1e-4 { continue }
            totalTangentialPx += mag
            count += 1
        }

        if count < 3 { return nil }

        // px/frame → meters/frame
        let pxPerFrame = totalTangentialPx / count
        let metersPerFrame = (pxPerFrame / fx) * depth

        let vTan = metersPerFrame * fps  // convert to m/s
        let omega = vTan / ballRadius    // ω = v / r

        return max(0, omega.isFinite ? omega : 0)
    }
}