//
//  EPnPSwift.swift
//  LaunchLab
//

import Foundation
import simd
import Accelerate

/// Minimal, deterministic EPnP solver in pure Swift + Accelerate.
///
/// Returns R, T ONLY — no velocities, no RS expansion.
/// Used as the base pose bootstrap (PoseSolver + RSPnP fallback).
///
/// This EPnP implementation:
///   • Uses explicit outer products (no simd_outer_product)
///   • Uses Accelerate SVD (no simd_float3x3.svd())
///   • Deterministic, allocation-light
///
struct EPnPSwift {
    
    struct Result {
        let R: simd_float3x3
        let T: SIMD3<Float>
        let isValid: Bool
    }
    
    // MARK: - Entry
    static func solve(
        imagePoints: [SIMD2<Float>],
        modelPoints: [SIMD3<Float>],
        intrinsics K: simd_float3x3
    ) -> Result? {
        
        let n = imagePoints.count
        guard n >= 4, n == modelPoints.count else { return nil }
        
        // Build M (2n × 12)
        let rows = 2 * n
        let cols = 12
        
        var M = [Double](repeating: 0, count: rows * cols)
        
        let fx = Double(K[0,0])
        let fy = Double(K[1,1])
        let cx = Double(K[0,2])
        let cy = Double(K[1,2])
        
        for i in 0..<n {
            let X = Double(modelPoints[i].x)
            let Y = Double(modelPoints[i].y)
            let Z = Double(modelPoints[i].z)
            
            let u = Double(imagePoints[i].x)
            let v = Double(imagePoints[i].y)
            
            let r0 = 2 * i
            let r1 = r0 + 1
            
            func write(_ r: Int, _ c: Int, _ value: Double) {
                M[r * cols + c] = value
            }
            
            // Row 0 (x-projection)
            write(r0, 0, fx * X + 0)
            write(r0, 1, fx * Y + 0)
            write(r0, 2, fx * Z + 0)
            write(r0, 3, fx * 1)
            write(r0, 4, 0)
            write(r0, 5, 0)
            write(r0, 6, 0)
            write(r0, 7, 0)
            write(r0, 8, -u * X)
            write(r0, 9, -u * Y)
            write(r0,10, -u * Z)
            write(r0,11, -u)
            
            // Row 1 (y-projection)
            write(r1, 0, 0)
            write(r1, 1, 0)
            write(r1, 2, 0)
            write(r1, 3, 0)
            write(r1, 4, fy * X + 0)
            write(r1, 5, fy * Y + 0)
            write(r1, 6, fy * Z + 0)
            write(r1, 7, fy * 1)
            write(r1, 8, -v * X)
            write(r1, 9, -v * Y)
            write(r1,10, -v * Z)
            write(r1,11, -v)
        }
        
        // Solve M * x = 0 using SVD — smallest singular vector
        var jobu:  Int8 = 65   // "A"
        var jobvt: Int8 = 65   // "A"
        
        // Immutable originals
        let m0 = __CLPK_integer(rows)
        let n0 = __CLPK_integer(cols)
        let lda0 = m0
        
        // Mutable LAPACK parameters
        var mLapack = m0
        var nLapack = n0
        var lda = lda0
        
        // Local working copies
        var a = M
        var s = [Double](repeating: 0.0, count: Int(min(m0, n0)))
        var uMat  = [Double](repeating: 0.0, count: Int(m0 * m0))
        var vtMat = [Double](repeating: 0.0, count: Int(n0 * n0))
        
        var workSize = __CLPK_integer(max(1, 5 * max(m0, n0)))
        var work = [Double](repeating: 0.0, count: Int(workSize))
        var info: __CLPK_integer = 0
        
        // --- Prepare LAPACK shadow copies to avoid exclusivity ---
        var mInput  = mLapack
        var nInput  = nLapack
        var ldaIn   = lda

        var mForU   = mLapack     // used ONLY for the U matrix leading dimension
        var nForVT  = nLapack     // used ONLY for the VT matrix leading dimension

        // --- SAFE LAPACK CALL ---
        dgesvd_(
            &jobu, &jobvt,
            &mInput, &nInput,     // <— THESE are the "true" m,n
            &a, &ldaIn,
            &s,
            &uMat, &mForU,        // <— SHADOW copy for U leading dimension
            &vtMat, &nForVT,      // <— SHADOW copy for VT leading dimension
            &work, &workSize,
            &info
        )
        
        if info != 0 { return nil }
        
        // extract smallest singular vector using IMMUTABLE n0
        let nn = Int(n0)
        let x = vtMat[(nn - 1) * nn ..< nn * nn]
        let xArr = Array(x)
        
        guard xArr.count == 12 else { return nil }
        
        // build rotation vector
        let rvec = SIMD9<Float>(
            Float(xArr[0]), Float(xArr[1]), Float(xArr[2]),
            Float(xArr[4]), Float(xArr[5]), Float(xArr[6]),
            Float(xArr[8]), Float(xArr[9]), Float(xArr[10])
        )
        
        let tvec = SIMD3<Float>(
            Float(xArr[3]), Float(xArr[7]), Float(xArr[11])
        )
        
        // Build rotation (normalize rows)
        let R = simd_float3x3(
            SIMD3(rvec[0], rvec[1], rvec[2]),
            SIMD3(rvec[3], rvec[4], rvec[5]),
            SIMD3(rvec[6], rvec[7], rvec[8])
        )
        
        let U = orthonormalize(R)
        return Result(R: U, T: tvec, isValid: true)
        
        // MARK: - Orthonormalize rotation
         func orthonormalize(_ R: simd_float3x3) -> simd_float3x3 {
            var c0 = R.columns.0
            var c1 = R.columns.1
            var c2 = R.columns.2

            c0 = simd_normalize(c0)
            c1 = simd_normalize(c1 - simd_dot(c0, c1) * c0)
            c2 = simd_cross(c0, c1)

            return simd_float3x3(c0, c1, c2)
        }
    }
    
    
    /// Helper 9-element SIMD
    typealias SIMD9<T: SIMDScalar> = SIMD9Storage<T>
    
    struct SIMD9Storage<T: SIMDScalar> {
        var a0, a1, a2, a3, a4, a5, a6, a7, a8: T
        
        init(_ a0: T, _ a1: T, _ a2: T,
             _ a3: T, _ a4: T, _ a5: T,
             _ a6: T, _ a7: T, _ a8: T)
        {
            self.a0 = a0; self.a1 = a1; self.a2 = a2
            self.a3 = a3; self.a4 = a4; self.a5 = a5
            self.a6 = a6; self.a7 = a7; self.a8 = a8
        }
        
        subscript(i: Int) -> T {
            switch i {
            case 0: return a0; case 1: return a1; case 2: return a2
            case 3: return a3; case 4: return a4; case 5: return a5
            case 6: return a6; case 7: return a7; case 8: return a8
            default: fatalError("SIMD9 index out of range")
            }
        }
    }
}
