//
//  RPEResiduals.swift
//  LaunchLab
//

import Foundation
import simd

public struct RPEResidual {
    public let id: Int
    public let observed: SIMD2<Float>
    public let projected: SIMD2<Float>
    public let errorVec: SIMD2<Float>
    public let errorMag: Float
}

public final class RPEResiduals {

    public init() {}

    public func compute(
        modelPoints: [SIMD3<Float>],
        imagePoints: [SIMD2<Float>],
        rotation R: simd_float3x3,
        translation T: SIMD3<Float>,
        intrinsics K: simd_float3x3
    ) -> [RPEResidual] {

        let count = min(modelPoints.count, imagePoints.count)
        if count == 0 { return [] }

        var out: [RPEResidual] = []
        out.reserveCapacity(count)

        for id in 0..<count {
            let obs = imagePoints[id]
            let world = modelPoints[id]

            let proj = PoseSolver.projectPoint(
                point: world,
                R: R,
                T: T,
                K: K
            )

            let err = obs &- proj
            let mag = simd_length(err)

            out.append(
                RPEResidual(
                    id: id,
                    observed: obs,
                    projected: proj,
                    errorVec: err,
                    errorMag: mag
                )
            )
        }

        return out.sorted { $0.id < $1.id }
    }
}