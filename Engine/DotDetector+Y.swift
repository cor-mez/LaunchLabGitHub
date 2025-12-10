//
// DotDetector+Y.swift
//

import Foundation
import Accelerate

extension DotDetector {

    internal func preprocessYROI(
        _ yROI: vImage_Buffer,
        gain: Float
    ) -> vImage_Buffer {

        let w = Int(yROI.width)
        let h = Int(yROI.height)
        guard w > 2, h > 2 else { return yROI }

        let g = max(0.5, min(3.0, gain))
        if abs(g - 1.0) < 0.001 {
            return yROI
        }

        let fRB = w * MemoryLayout<Float>.stride
        let fBytes = fRB * h
        guard let fData = malloc(fBytes) else { return yROI }

        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: fRB
        )

        var yCopy = yROI
        vImageConvert_Planar8toPlanarF(
            &yCopy,
            &fBuf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        let count = vDSP_Length(w*h)
        let fPtr = fBuf.data.assumingMemoryBound(to: Float.self)
        var gg = g
        vDSP_vsmul(fPtr, 1, &gg, fPtr, 1, count)

        var lo: Float = 0
        var hi: Float = 255
        vDSP_vclip(fPtr, 1, &lo, &hi, fPtr, 1, count)

        let oRB = w
        let oBytes = w*h
        guard let oData = malloc(oBytes) else {
            free(fData)
            return yROI
        }

        var out = vImage_Buffer(
            data: oData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: oRB
        )

        vImageConvert_PlanarFtoPlanar8(&fBuf, &out, 1.0, 0.0, vImage_Flags(kvImageNoFlags))

        free(fData)
        return out
    }
}
