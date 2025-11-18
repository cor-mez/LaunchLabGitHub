import Foundation
import simd

final class PoseSolver {

    struct Pose {
        let R: simd_float3x3
        let T: SIMD3<Float>
        let reprojectionError: Float
    }

    func solve(
        imagePoints: [SIMD2<Float>],
        intrinsics: simd_float3x3
    ) -> Pose? {

        let model = MarkerPattern.model3D
        let count = min(imagePoints.count, model.count)
        if count < 4 { return nil }

        var modelFlat = [Float](repeating: 0, count: count*3)
        var imageFlat = [Float](repeating: 0, count: count*2)

        for i in 0..<count {
            modelFlat[i*3+0] = model[i].x
            modelFlat[i*3+1] = model[i].y
            modelFlat[i*3+2] = model[i].z

            imageFlat[i*2+0] = imagePoints[i].x
            imageFlat[i*2+1] = imagePoints[i].y
        }

        let fx = intrinsics[0,0]
        let fy = intrinsics[1,1]
        let cx = intrinsics[0,2]
        let cy = intrinsics[1,2]

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
