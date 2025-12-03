// File: Engine/RSPnPSolver.swift
//
//  RSPnPSolver.swift
//  LaunchLab
//
//  Rolling-shutter SE(3) pose solver (V1.5, Swift + simd) with
//  flicker-weighted correspondences.
//

import Foundation
import CoreGraphics
import simd

final class RSPnPSolver {

    // MARK: - Constants

    /// Rolling-shutter readout time per frame (seconds).
    private let readoutTime: Float = 0.0052

    /// Physical ball radius in meters (must match MarkerPattern).
    private let realBallRadius: Float = 0.021335

    /// Validity residual threshold (pixels).
    private let maxValidResidual: Float = 3.0

    /// Assumed frame interval for launch captures (240 fps).
    private let frameInterval: Float = 1.0 / 240.0

    func solve(
        window: RSWindow,
        intrinsics: CameraIntrinsics,
        rowGradient: [Float]
    ) -> RSPnPResult {

        // Identity rotation (frozen V1.5)
        let R = simd_float3x3(diagonal: SIMD3<Float>(1, 1, 1))
        let zero3 = SIMD3<Float>(repeating: 0)

        func invalidResult(residual: Float = .greatestFiniteMagnitude) -> RSPnPResult {
            return RSPnPResult(
                R: R,
                t: zero3,
                w: zero3,
                v: zero3,
                residual: residual,
                isValid: false
            )
        }

        let frames = window.frames
        guard frames.count == 3 else { return invalidResult() }

        // Temporary constant depth assumption
        let nominalDepth: Float = 2.5

        // -----------------------------------------
        // 2D → 3D Backprojection of ball center
        // -----------------------------------------
        var centers3D: [SIMD3<Float>] = []
        centers3D.reserveCapacity(3)

        for frame in frames {
            guard let centerPx = estimateBallCenter2D(from: frame) else {
                return invalidResult()
            }

            let c3 = backProject(centerPx: centerPx,
                                 depth: nominalDepth,
                                 intrinsics: intrinsics)

            if !allFinite(c3) { return invalidResult() }
            centers3D.append(c3)
        }

        guard centers3D.count == 3 else { return invalidResult() }

        // Translation = middle frame center
        let t = centers3D[1]

        // Velocity = central finite difference
        let dt: Float = 1.0 / 240.0
        let v = (centers3D[2] - centers3D[0]) / (2 * dt)

        // No rotation solve yet
        let w = zero3

        // Rolling-shutter weighted residual
        let residual = computeResidual(
            frames: frames,
            intrinsics: intrinsics,
            R: R,
            t: t,
            w: w,
            v: v,
            rowGradient: rowGradient
        )

        // Validity
        let invalid =
            !residual.isFinite ||
            !allFinite(t) ||
            !allFinite(v) ||
            nominalDepth <= 0 ||
            t.z <= 0

        let isValid = !invalid && residual < maxValidResidual

        return RSPnPResult(
            R: R,
            t: t,
            w: w,
            v: v,
            residual: residual,
            isValid: isValid
        )
    }

    // MARK: - Helpers (ball center & back-projection)

    /// Uses residual 100 (ROI center) when present; falls back to dot centroid.
    private func estimateBallCenter2D(from frame: VisionFrameData) -> CGPoint? {
        if let residuals = frame.residuals,
           let roi = residuals.first(where: { $0.id == 100 }) {
            return CGPoint(
                x: CGFloat(roi.error.x),
                y: CGFloat(roi.error.y)
            )
        }

        let dots = frame.dots
        guard !dots.isEmpty else { return nil }

        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for d in dots {
            sx += d.position.x
            sy += d.position.y
        }
        let invN = 1.0 / CGFloat(dots.count)
        return CGPoint(x: sx * invN, y: sy * invN)
    }

    private func backProject(
        centerPx: CGPoint,
        depth: Float,
        intrinsics: CameraIntrinsics
    ) -> SIMD3<Float> {
        let xNorm = (Float(centerPx.x) - intrinsics.cx) / intrinsics.fx
        let yNorm = (Float(centerPx.y) - intrinsics.cy) / intrinsics.fy
        let dir = simd_normalize(SIMD3<Float>(xNorm, yNorm, 1.0))
        return dir * depth
    }

    private func allFinite(_ v: SIMD3<Float>) -> Bool {
        return v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    // MARK: - Flicker-weighted residual (RS + NN matching)

    private func computeResidual(
        frames: [VisionFrameData],
        intrinsics: CameraIntrinsics,
        R: simd_float3x3,
        t: SIMD3<Float>,
        w: SIMD3<Float>,
        v: SIMD3<Float>,
        rowGradient: [Float]
    ) -> Float {

        let modelPoints = MarkerPattern.model3D    // 72-dot 3D pattern
        guard !modelPoints.isEmpty else {
            return .greatestFiniteMagnitude
        }

        var sumWeightedErr2: Float = 0
        var sumWeights: Float = 0
        let lambda: Float = 6.0

        for frame in frames {
            let height = max(frame.height, 1)
            let invH = 1.0 / Float(height)

            for dot in frame.dots {
                // Row index for this dot.
                let rowIndex = clampRowIndex(
                    Int(dot.position.y.rounded()),
                    height: height
                )

                // Flicker gradient at this row.
                let rowIdxGradient: Int
                if rowGradient.isEmpty {
                    rowIdxGradient = rowIndex
                } else {
                    rowIdxGradient = max(0, min(rowGradient.count - 1, rowIndex))
                }

                let g: Float
                if rowGradient.isEmpty {
                    g = 0.0
                } else {
                    g = fabsf(rowGradient[rowIdxGradient])
                }
                let weight = 1.0 / (1.0 + lambda * g)

                // Rolling-shutter dt for this dot (frozen model).
                let rowF = Float(rowIndex)
                let dt = (rowF * invH) * readoutTime

                // For this observed dot, find nearest projected model point.
                var bestD2: Float = .greatestFiniteMagnitude

                for X in modelPoints {
                    let proj = projectRS(
                        X: X,
                        dt: dt,
                        intrinsics: intrinsics,
                        R: R,
                        t: t,
                        w: w,
                        v: v
                    )

                    // proj.z is camera-space Z; skip points behind camera.
                    if !proj.z.isFinite || proj.z <= 0 {
                        continue
                    }

                    let u = proj.x
                    let v2 = proj.y

                    let du = Float(dot.position.x) - u
                    let dv = Float(dot.position.y) - v2
                    let d2 = du * du + dv * dv

                    if d2 < bestD2 {
                        bestD2 = d2
                    }
                }

                if bestD2 < .greatestFiniteMagnitude {
                    sumWeightedErr2 += weight * bestD2
                    sumWeights += weight
                }
            }
        }

        guard sumWeights > 0 else {
            return .greatestFiniteMagnitude
        }

        return sqrt(sumWeightedErr2 / sumWeights)
    }

    private func clampRowIndex(_ row: Int, height: Int) -> Int {
        if row < 0 { return 0 }
        if row >= height { return height - 1 }
        return row
    }

    /// Projects a ball-frame point with continuous-time RS SE(3) model.
    ///
    /// x_cam = R * X
    ///       + t
    ///       + (w × X) * dt
    ///       + v * dt
    ///
    /// Returns (u, v, z) where u,v are pixel coords and z is camera-space depth.
    private func projectRS(
        X: SIMD3<Float>,
        dt: Float,
        intrinsics: CameraIntrinsics,
        R: simd_float3x3,
        t: SIMD3<Float>,
        w: SIMD3<Float>,
        v: SIMD3<Float>
    ) -> SIMD3<Float> {

        let RX = R * X
        let motionOffset = simd_cross(w, X) * dt + v * dt
        let Xc = RX + t + motionOffset

        let z = Xc.z
        if !z.isFinite || z <= 0 {
            return SIMD3<Float>(.nan, .nan, z)
        }

        let invZ = 1.0 / z
        let u = intrinsics.fx * Xc.x * invZ + intrinsics.cx
        let v2 = intrinsics.fy * Xc.y * invZ + intrinsics.cy

        return SIMD3<Float>(u, v2, z)
    }
}
