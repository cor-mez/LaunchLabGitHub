//
//  PoseSolver.swift
//  LaunchLab
//

import Foundation
import simd
import Accelerate

final class PoseSolver {

    struct Pose {
        let R: simd_float3x3
        let T: SIMD3<Float>
        let reprojectionError: Float
    }

    // ============================================================
    // MARK: - Public Solve Entry
    // ============================================================
    func solve(
        imagePoints: [SIMD2<Float>],
        intrinsics K: simd_float3x3
    ) -> Pose? {

        let model = MarkerPattern.model3D
        let N = min(imagePoints.count, model.count)
        if N < 4 { return nil }

        // --------------------------------------------------------
        // 1. EPnP Bootstrap (using correct signature)
        // --------------------------------------------------------
        guard
            let boot = EPnPSwift.solve(
                imagePoints: imagePoints,
                modelPoints: model,
                intrinsics: K
            ),
            boot.isValid
        else { return nil }

        var R = boot.R
        var T = boot.T

        // --------------------------------------------------------
        // 2. Nonlinear refinement
        // --------------------------------------------------------
        for _ in 0..<6 {
            
            var J = [Float]()
            var r = [Float]()
            J.reserveCapacity(N*12)
            r.reserveCapacity(N*2)
            
            for i in 0..<N {
                
                let Xw = model[i]
                let p  = imagePoints[i]
                let Xc = R * Xw + T
                
                if Xc.z <= 1e-6 { continue }
                
                let proj = Self.projectPoint(Xc, intrinsics: K)
                
                r.append(p.x - proj.x)
                r.append(p.y - proj.y)
                
                let fx = K[0,0]
                let fy = K[1,1]
                
                let X = Xc.x
                let Y = Xc.y
                let Z = Xc.z
                let Z2 = Z*Z
                
                let du_dX = fx/Z
                let du_dZ = -(fx*X)/Z2
                let dv_dY = fy/Z
                let dv_dZ = -(fy*Y)/Z2
                
                func push(_ d: SIMD3<Float>) {
                    let jx = du_dX*d.x + du_dZ*d.z
                    let jy = dv_dY*d.y + dv_dZ*d.z
                    J.append(jx)
                    J.append(jy)
                }
                
                push(SIMD3(0, Xw.z, -Xw.y))
                push(SIMD3(-Xw.z, 0, Xw.x))
                push(SIMD3(Xw.y, -Xw.x, 0))
                
                push(SIMD3(1,0,0))
                push(SIMD3(0,1,0))
                push(SIMD3(0,0,1))
            }
            
            let m = r.count
            let n = 6
            if m < n { break }
            
            var JTJ = [Float](repeating: 0, count: n*n)
            var JTr = [Float](repeating: 0, count: n)
            
            for row in 0..<m {
                let ri = r[row]
                for col in 0..<n {
                    JTr[col] += J[row*n + col] * ri
                }
            }
            
            for i in 0..<n {
                for j in 0..<n {
                    var sum: Float = 0
                    for k in 0..<m {
                        sum += J[k*n+i] * J[k*n+j]
                    }
                    JTJ[i*n+j] = sum
                }
            }
            
            // Before LAPACK: define dimensions
            var nLocal: Int32 = Int32(n)   // dimension of JTJ (6x6)
            var nrhsLocal: Int32 = 1       // single RHS
            
            // COPY matrices before passing to LAPACK — required for exclusivity
            var localA = JTJ               // 6×6
            var localB = JTr               // 6×1
            var ipiv = [Int32](repeating: 0, count: n)
            var info: Int32 = 0
            
            // Separate LDAs to avoid exclusivity
            var ldaForA: Int32 = nLocal    // leading dimension of A
            var ldbForB: Int32 = nLocal    // leading dimension of B
            
            // --- SAFE LAPACK CALL ---
            sgesv_(
                &nLocal,        // N
                &nrhsLocal,     // NRHS
                &localA,        // A
                &ldaForA,       // LDA
                &ipiv,          // IPIV
                &localB,        // B (solution)
                &ldbForB,       // LDB
                &info           // INFO
            )
            
            if info != 0 { break }
            
            // δ = solution
            let δ = localB   // length 6
            
            let w = SIMD3<Float>(δ[0], δ[1], δ[2])
            let v = SIMD3<Float>(δ[3], δ[4], δ[5])
            
            R = expSO3(w) * R
            T += v
        }

        let err = computeReprojError(R, T, model, imagePoints, K)

        return Pose(R: R, T: T, reprojectionError: err)
    }


    // MARK: Helpers

    static func projectPoint(_ p: SIMD3<Float>, intrinsics K: simd_float3x3) -> SIMD2<Float> {
        SIMD2(
            (K[0,0]*p.x + K[0,2]*p.z) / p.z,
            (K[1,1]*p.y + K[1,2]*p.z) / p.z
        )
    }

    fileprivate func expSO3(_ w: SIMD3<Float>) -> simd_float3x3 {
        let θ = simd_length(w)
        if θ < 1e-9 { return matrix_identity_float3x3 }

        let k = w / θ
        let K = simd_float3x3(rows: [
            SIMD3( 0, -k.z,  k.y),
            SIMD3( k.z, 0,  -k.x),
            SIMD3(-k.y, k.x,  0)
        ])

        return matrix_identity_float3x3
             + sin(θ)*K
             + (1 - cos(θ))*(K*K)
    }

    fileprivate func computeReprojError(
        _ R: simd_float3x3,
        _ T: SIMD3<Float>,
        _ model: [SIMD3<Float>],
        _ image: [SIMD2<Float>],
        _ K: simd_float3x3
    ) -> Float {

        let N = min(model.count, image.count)
        if N == 0 { return 0 }

        var sum: Float = 0

        for i in 0..<N {
            let Xc = R * model[i] + T
            let p = Self.projectPoint(Xc, intrinsics: K)
            let dx = image[i].x - p.x
            let dy = image[i].y - p.y
            sum += dx*dx + dy*dy
        }

        return sqrt(sum / Float(N))
    }
}
