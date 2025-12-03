// File: Engine/DotDetector+Y.swift
//
//  Y-path preprocessing module for DotDetector.
//

import Foundation
import Accelerate

extension DotDetector {

    func preprocessYROI(
        _ yROI: vImage_Buffer,
        gain: Float
    ) -> vImage_Buffer {

        let w = Int(yROI.width)
        let h = Int(yROI.height)

        if w < 8 || h < 8 {
            return yROI
        }

        let g = max(0.5, min(2.0, gain))
        if abs(g - 1.0) < 0.0001 {
            return yROI
        }

        let floatRowBytes = w * MemoryLayout<Float>.stride
        let floatByteCount = floatRowBytes * h

        guard let fData = malloc(floatByteCount) else {
            return yROI
        }

        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: floatRowBytes
        )

        var yCopy = yROI
        vImageConvert_Planar8toPlanarF(
            &yCopy,
            &fBuf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        let count = vDSP_Length(w * h)
        let fPtr = fBuf.data.assumingMemoryBound(to: Float.self)
        var gVar = g
        vDSP_vsmul(fPtr, 1, &gVar, fPtr, 1, count)

        var minVal: Float = 0.0
        var maxVal: Float = 255.0
        vDSP_vclip(fPtr, 1, &minVal, &maxVal, fPtr, 1, count)

        let outRowBytes = w
        let outByteCount = outRowBytes * h

        guard let outData = malloc(outByteCount) else {
            free(fData)
            return yROI
        }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: outRowBytes
        )

        vImageConvert_PlanarFtoPlanar8(
            &fBuf,
            &outBuf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        free(fData)
        return outBuf
    }
}