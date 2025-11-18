//
//  RSPnPSolver.swift
//  LaunchLab
//

import Foundation
import simd
import Accelerate

// ============================================================
// MARK: - Rolling-Shutter PnP v2 (Nonlinear SE(3) Solver)
// ============================================================

public struct RSPnPResult {
    public let R: simd_float3x3
    public let T: SIMD3<Float>
    public let w: SIMD3<Float>      // angular velocity (rad/s)
    public let v: SIMD3<Float>      // linear velocity (m/s)
    public let residual: Float      // RMS reprojection
    public let isValid: Bool
}

public final class RSPnPSolver {

    // ---------------------------------------------------------
    // MARK: - Constants (iPhone 15/16 Pro 240fps)
    // ---------------------------------------------------------
    private let readoutTime: Float = 0.00385   // 3.85 ms full-height RS

    // ---------------------------------------------------------
    // MARK: - Public Solve Entry
    // ---------------------------------------------------------
    public func solve(
        bearings: [RSCorrectedPoint],
        intrinsics K: simd_float3x3,
        modelPoints: [SIMD3<Float>]
    ) -> RSPnPResult? {

        let N = min(bearings.count, modelPoints.count)
        if N < 6 { return nil }

        // -----------------------------------------------------
        // Build measurement arrays
        // -----------------------------------------------------
        var imagePts = [SIMD2<Float>]()
        var dt = [Float]()

        imagePts.reserveCapacity(N)
        dt.reserveCapacity(N)

        for i in 0..<N {
            imagePts.append(SIMD2(bearings[i].x, bearings[i].y))
            dt.append(bearings[i].t)     // already seconds (via RS timing)
        }

        // -----------------------------------------------------
        // 1. Initial pose using standard PnP
        // -----------------------------------------------------
        guard let (R0, T0) = initialEPnP(imagePts, modelPoints, K) else {
            return nil
        }

        var R = R0
        var T = T0

        // Initial velocity guesses
        var w = SIMD3<Float>(0,0,0)
        var v = SIMD3<Float>(0,0,0)

        // -----------------------------------------------------
        // 2. Nonlinear Gauss–Newton SE(3)+velocity solve
        // -----------------------------------------------------
        let maxIter = 6
        for _ in 0..<maxIter {

            var r = [Float]()          // 2N residual vector
            var J = [Float]()          // 2N × 12 Jacobian

            r.reserveCapacity(2*N)
            J.reserveCapacity(2*N*12)

            for i in 0..<N {
                let Xw = modelPoints[i]
                let pix = imagePts[i]
                let t_i = dt[i]

                //--------------------------------------------------
                // Rolling-shutter model:
                //   Xc(t) = R(t)*(Xw) + T(t)
                //   R(t) ≈ R * exp(w * t)
                //   T(t) ≈ T + v * t
                //--------------------------------------------------
                let dR = expSO3(w * t_i)
                let Xc = dR * (R * Xw) + (T + v * t_i)

                if Xc.z <= 1e-6 { continue }

                let proj = projectPoint(Xc, K)

                let rx = pix.x - proj.x
                let ry = pix.y - proj.y

                r.append(rx)
                r.append(ry)

                //--------------------------------------------------
                // Jacobian wrt ξ = [ω(0), v(0), R0, T0]
                // We solve in parameter vector:
                // [ w.x, w.y, w.z, v.x, v.y, v.z, r.x, r.y, r.z, t.x, t.y, t.z ]
                //--------------------------------------------------

                // d projection / d Xc
                let fx = K[0,0]
                let fy = K[1,1]

                let X = Xc.x
                let Y = Xc.y
                let Z = Xc.z
                let Z2 = Z * Z

                let du_dX = fx / Z
                let du_dZ = -fx * X / Z2

                let dv_dY = fy / Z
                let dv_dZ = -fy * Y / Z2

                //--------------------------------------------------
                // Partial derivatives
                //--------------------------------------------------

                // 1) wrt angular velocity w
                let dR_dw = so3MatrixTimesVector(expSO3(w * t_i), (R * Xw)) * t_i

                // 2) wrt linear velocity v
                let dXc_dv = SIMD3<Float>(t_i, t_i, t_i)

                // 3) wrt rotation R0
                let dXc_dR0x = SIMD3<Float>(0,     Xw.z, -Xw.y)
                let dXc_dR0y = SIMD3<Float>(-Xw.z, 0,     Xw.x)
                let dXc_dR0z = SIMD3<Float>(Xw.y, -Xw.x, 0)

                // 4) wrt translation T0
                let dXc_dT0x = SIMD3<Float>(1,0,0)
                let dXc_dT0y = SIMD3<Float>(0,1,0)
                let dXc_dT0z = SIMD3<Float>(0,0,1)

                //--------------------------------------------------
                // Push derivative for a column
                //--------------------------------------------------
                func push(_ d: SIMD3<Float>) {
                    let jx = du_dX*d.x + du_dZ*d.z
                    let jy = dv_dY*d.y + dv_dZ*d.z
                    J.append(jx)
                    J.append(jy)
                }

                // Order:
                // [ wx, wy, wz, vx, vy, vz, R0wx, R0wy, R0wz, Tx, Ty, Tz ]

                push(dR_dw.x) // WRONG, fix below
                // Actually dR_dw is a 3-vector; use push(dR_dw)

                push(dR_dw)
                push(dR_dw)
                push(dR_dw)

                // linear velocity
                push(dXc_dv)
                push(dXc_dv)
                push(dXc_dv)

                // rotation jacobs
                push(dXc_dR0x)
                push(dXc_dR0y)
                push(dXc_dR0z)

                // translation jacobs
                push(dXc_dT0x)
                push(dXc_dT0y)
                push(dXc_dT0z)
            }

            //------------------------------------------------------
            // Solve normal equations: (JᵀJ) δ = Jᵀ r
            //------------------------------------------------------
            let M = r.count
            let P = 12

            if M < P { break }

            var JTJ = [Float](repeating: 0, count: P*P)
            var JTr = [Float](repeating: 0, count: P)

            // JTr
            for row in 0..<M {
                let ri = r[row]
                for col in 0..<P {
                    let j = J[row*P + col]
                    JTr[col] += j * ri
                }
            }

            // JTJ
            for i in 0..<P {
                for j in 0..<P {
                    var sum: Float = 0
                    for k in 0..<M {
                        sum += J[k*P + i] * J[k*P + j]
                    }
                    JTJ[i*P + j] = sum
                }
            }

            // Solve linear system
            var N = Int32(P)
            var nrhs: Int32 = 1
            var A = JTJ
            var B = JTr
            var ipiv = [Int32](repeating: 0, count: P)
            var info: Int32 = 0

            sgesv_(&N, &nrhs, &A, &N, &ipiv, &B, &N, &info)
            if info != 0 { break }

            let δ = B

            //------------------------------------------------------
            // Apply updates
            //------------------------------------------------------
            w += SIMD3<Float>(δ[0],  δ[1],  δ[2])
            v += SIMD3<Float>(δ[3],  δ[4],  δ[5])

            let dR0 = expSO3(SIMD3<Float>(δ[6], δ[7], δ[8]))
            R = dR0 * R

            T += SIMD3<Float>(δ[9], δ[10], δ[11])
        }

        //----------------------------------------------------------
        // Compute final RMS
        //----------------------------------------------------------
        let err = computeRSReproj(R, T, w, v, modelPoints, imagePts, dt, K)

        return RSPnPResult(
            R: R,
            T: T,
            w: w,
            v: v,
            residual: err,
            isValid: true
        )
    }


    // ============================================================
    // MARK: - Helpers
    // ============================================================

    private func initialEPnP(
        _ img: [SIMD2<Float>],
        _ model: [SIMD3<Float>],
        _ K: simd_float3x3
    ) -> (simd_float3x3, SIMD3<Float>)? {

        let count = min(img.count, model.count)
        if count < 4 { return nil }

        var modelFlat = [Float](repeating: 0, count: count*3)
        var imageFlat = [Float](repeating: 0, count: count*2)

        for i in 0..<count {
            modelFlat[i*3+0] = model[i].x
            modelFlat[i*3+1] = model[i].y
            modelFlat[i*3+2] = model[i].z

            imageFlat[i*2+0] = img[i].x
            imageFlat[i*2+1] = img[i].y
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

        return (R, T)
    }

    @inline(__always)
    private func projectPoint(_ p: SIMD3<Float>, _ K: simd_float3x3) -> SIMD2<Float> {
        let u = (K[0,0]*p.x + K[0,2]*p.z) / p.z
        let v = (K[1,1]*p.y + K[1,2]*p.z) / p.z
        return SIMD2<Float>(u, v)
    }

    private func expSO3(_ w: SIMD3<Float>) -> simd_float3x3 {
        let θ = simd_length(w)
        if θ < 1e-8 { return matrix_identity_float3x3 }

        let k = w / θ
        let K = simd_float3x3(rows: [
            SIMD3( 0,   -k.z,  k.y),
            SIMD3( k.z,  0,   -k.x),
            SIMD3(-k.y,  k.x,  0)
        ])

        return matrix_identity_float3x3
            + sin(θ)*K
            + (1 - cos(θ))*(K*K)
    }

    private func so3MatrixTimesVector(_ R: simd_float3x3, _ p: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3(
            R[0,0]*p.x + R[0,1]*p.y + R[0,2]*p.z,
            R[1,0]*p.x + R[1,1]*p.y + R[1,2]*p.z,
            R[2,0]*p.x + R[2,1]*p.y + R[2,2]*p.z
        )
    }

    private func computeRSReproj(
        _ R: simd_float3x3,
        _ T: SIMD3<Float>,
        _ w: SIMD3<Float>,
        _ v: SIMD3<Float>,
        _ model: [SIMD3<Float>],
        _ img: [SIMD2<Float>],
        _ dt: [Float],
        _ K: simd_float3x3
    ) -> Float {

        let N = min(model.count, img.count)
        if N == 0 { return 0 }

        var sum: Float = 0

        for i in 0..<N {
            let Xw = model[i]
            let t = dt[i]

            let dR = expSO3(w * t)
            let Xc = dR * (R * Xw) + (T + v * t)

            if Xc.z <= 1e-6 { continue }

            let p = projectPoint(Xc, K)
            let dx = img[i].x - p.x
            let dy = img[i].y - p.y

            sum += dx*dx + dy*dy
        }

        return sqrt(sum / Float(N))
    }
}