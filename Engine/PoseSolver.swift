//
//  PoseSolver.swift
//  LaunchLab
//

import Foundation
import simd
import Accelerate

// ============================================================
// MARK: - PoseSolver v2
// Full Nonlinear Gauss–Newton SE(3) Solver
// ============================================================

final class PoseSolver {

    struct Pose {
        let R: simd_float3x3
        let T: SIMD3<Float>
        let reprojectionError: Float
    }

    // ---------------------------------------------------------
    // MARK: - Public Solve Entry
    // ---------------------------------------------------------
    func solve(
        imagePoints: [SIMD2<Float>],
        intrinsics K: simd_float3x3
    ) -> Pose? {

        let model = MarkerPattern.model3D
        let count = min(imagePoints.count, model.count)
        if count < 4 { return nil }

        // ------------------------------------------
        // 1) Initial EPnP pose (fast coarse estimate)
        // ------------------------------------------
        guard let initPose = initialEPnP(imagePoints, model, K, count) else {
            return nil
        }

        var R = initPose.R
        var T = initPose.T

        // ------------------------------------------
        // 2) Nonlinear optimization (Gauss–Newton)
        // ------------------------------------------
        let maxIter = 6
        for _ in 0..<maxIter {

            var J = [Float]()
            var r = [Float]()

            J.reserveCapacity(count * 2 * 6)
            r.reserveCapacity(count * 2)

            // Loop all points
            for i in 0..<count {
                let Xw = model[i]             // world/model point
                let p  = imagePoints[i]       // observed pixel

                // Camera coordinates
                let Xc = R * Xw + T

                if Xc.z <= 1e-6 { continue }

                // Project
                let proj = PoseSolver.projectPoint(Xc, intrinsics: K)

                // Residual: observed - predicted
                let rx = p.x - proj.x
                let ry = p.y - proj.y

                r.append(rx)
                r.append(ry)

                let fx = K[0,0]
                let fy = K[1,1]

                let X = Xc.x
                let Y = Xc.y
                let Z = Xc.z
                let Z2 = Z * Z

                // d projection / d Xc
                let du_dX = fx / Z
                let du_dZ = -fx * X / Z2

                let dv_dY = fy / Z
                let dv_dZ = -fy * Y / Z2

                // dXc/dξ (SE3 twist)
                let dXc_dwx = SIMD3<Float>(0,       Xw.z,  -Xw.y)
                let dXc_dwy = SIMD3<Float>(-Xw.z,   0,      Xw.x)
                let dXc_dwz = SIMD3<Float>(Xw.y,   -Xw.x,   0)

                let dXc_dvx = SIMD3<Float>(1,0,0)
                let dXc_dvy = SIMD3<Float>(0,1,0)
                let dXc_dvz = SIMD3<Float>(0,0,1)

                // push rows into J
                func push(_ d: SIMD3<Float>) {
                    let jx = du_dX * d.x + du_dZ * d.z
                    let jy = dv_dY * d.y + dv_dZ * d.z
                    J.append(jx)
                    J.append(jy)
                }

                // Order: w.x, w.y, w.z, v.x, v.y, v.z
                push(dXc_dwx)
                push(dXc_dwy)
                push(dXc_dwz)
                push(dXc_dvx)
                push(dXc_dvy)
                push(dXc_dvz)
            }

            let m = r.count        // residual count = 2*N
            let n = 6              // twist dimension

            if m < n { break }

            // Form normal equations: (JᵀJ) δ = Jᵀ r
            var JTJ = [Float](repeating: 0, count: n*n)
            var JTr = [Float](repeating: 0, count: n)

            // JTr
            for row in 0..<m {
                let ri = r[row]
                for col in 0..<n {
                    let j = J[row*n + col]
                    JTr[col] += j * ri
                }
            }

            // JTJ
            for i in 0..<n {
                for j in 0..<n {
                    var sum: Float = 0
                    for k in 0..<m {
                        sum += J[k*n + i] * J[k*n + j]
                    }
                    JTJ[i*n + j] = sum
                }
            }

            // Solve linear system
            var N = Int32(n)
            var nrhs: Int32 = 1
            var ipiv = [Int32](repeating: 0, count: n)
            var A = JTJ
            var B = JTr
            var info: Int32 = 0

            sgesv_(&N, &nrhs, &A, &N, &ipiv, &B, &N, &info)
            if info != 0 { break }

            let δ = B

            let w = SIMD3<Float>(δ[0], δ[1], δ[2])
            let v = SIMD3<Float>(δ[3], δ[4], δ[5])

            // update rotation using exp(w)
            let dR = expSO3(w)
            R = dR * R

            // update translation
            T += v
        }

        let finalErr = computeReprojError(R, T, model, imagePoints, K)

        return Pose(R: R, T: T, reprojectionError: finalErr)
    }


    // ---------------------------------------------------------
    // MARK: - EPnP Bootstrap
    // ---------------------------------------------------------
    private func initialEPnP(
        _ image: [SIMD2<Float>],
        _ model: [SIMD3<Float>],
        _ K: simd_float3x3,
        _ count: Int
    ) -> Pose? {

        var modelFlat = [Float](repeating: 0, count: count * 3)
        var imageFlat = [Float](repeating: 0, count: count * 2)

        for i in 0..<count {
            modelFlat[i*3+0] = model[i].x
            modelFlat[i*3+1] = model[i].y
            modelFlat[i*3+2] = model[i].z

            imageFlat[i*2+0] = image[i].x
            imageFlat[i*2+1] = image[i].y
        }

        let fx = K[0,0]
        let fy = K[1,1]
        let cx = K[0,2]
        let cy = K[1,2]

        var Rflat = [Float](repeating: 0, count: 9)
        var Tflat = [Float](repeating: 0, count: 3)
        var err: Float = -1

        let ok = ll_solveEPnP(
            modelFlat,
            imageFlat,
            Int32(count),
            fx, fy, cx, cy,
            &Rflat,
            &Tflat,
            &err
        )
        if ok == 0 { return nil }

        let R = simd_float3x3(rows: [
            SIMD3(Rflat[0], Rflat[1], Rflat[2]),
            SIMD3(Rflat[3], Rflat[4], Rflat[5]),
            SIMD3(Rflat[6], Rflat[7], Rflat[8])
        ])

        let T = SIMD3(Tflat[0], Tflat[1], Tflat[2])

        return Pose(R: R, T: T, reprojectionError: err)
    }
}


// ============================================================
// MARK: - Helpers
// ============================================================

extension PoseSolver {

    // ---------------------------------------------------------
    // Projection helper (used by RPE overlay)
    // ---------------------------------------------------------
    @inline(__always)
    public static func projectPoint(_ p: SIMD3<Float>, intrinsics K: simd_float3x3) -> SIMD2<Float> {
        let u = (K[0,0] * p.x + K[0,2] * p.z) / p.z
        let v = (K[1,1] * p.y + K[1,2] * p.z) / p.z
        return SIMD2<Float>(u, v)
    }

    // ---------------------------------------------------------
    // SO(3) exponential map
    // ---------------------------------------------------------
    fileprivate func expSO3(_ w: SIMD3<Float>) -> simd_float3x3 {
        let θ = simd_length(w)
        if θ < 1e-9 { return matrix_identity_float3x3 }

        let k = w / θ
        let K = simd_float3x3(rows: [
            SIMD3<Float>(0,     -k.z,   k.y),
            SIMD3<Float>(k.z,   0,     -k.x),
            SIMD3<Float>(-k.y,  k.x,    0)
        ])

        return matrix_identity_float3x3
             + sin(θ) * K
             + (1 - cos(θ)) * (K * K)
    }

    // ---------------------------------------------------------
    // RMS reprojection error
    // ---------------------------------------------------------
    fileprivate func computeReprojError(
        _ R: simd_float3x3,
        _ T: SIMD3<Float>,
        _ model: [SIMD3<Float>],
        _ image: [SIMD2<Float>],
        _ K: simd_float3x3
    ) -> Float {

        let count = min(model.count, image.count)
        if count == 0 { return 0 }

        var sum: Float = 0

        for i in 0..<count {
            let Xc = R * model[i] + T
            let p = PoseSolver.projectPoint(Xc, intrinsics: K)

            let dx = image[i].x - p.x
            let dy = image[i].y - p.y
            sum += dx*dx + dy*dy
        }

        return sqrt(sum / Float(count))
    }
}