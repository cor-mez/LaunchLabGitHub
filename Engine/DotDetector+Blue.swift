// File: Engine/DotDetector+Blue.swift
//
//  Blue-channel normalization module for DotDetector.
//  Converts a half-resolution Cb ROI into a contrast-amplified Planar8
//  ROI suitable for SR and FAST9.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

extension DotDetector {

    /// Normalize Cb ROI (half-res) into a Planar8 ROI suitable for SR + FAST9.
    ///
    /// - Parameters:
    ///   - cbROI: half-resolution Cb plane crop (Planar8) passed inout.
    ///   - roiFullRect: full-frame ROI (unused here but kept for API parity).
    ///
    /// - Returns:
    ///   New Planar8 vImage_Buffer (malloc-owned), or nil to signal fallback.
    ///
    func normalizeBlueROI(
        cbROI: inout vImage_Buffer,
        roiFullRect: CGRect
    ) -> vImage_Buffer? {

        let w = Int(cbROI.width)
        let h = Int(cbROI.height)
        guard w >= 8, h >= 8 else { return nil }

        // Clamp gains to safe ranges.
        let chromaGain = max(1.0, min(8.0, config.blueChromaGain))
        let pfGain = max(0.5, min(2.0, config.preFilterGain))

        // Allocate float buffer (PlanarF)
        let floatRowBytes = w * MemoryLayout<Float>.stride
        let floatByteCount = floatRowBytes * h

        guard let fData = malloc(floatByteCount) else {
            return nil
        }

        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: floatRowBytes
        )

        // Convert Planar8 → PlanarF with offset -128 to center at 0.
        vImageConvert_Planar8toPlanarF(
            &cbROI,
            &fBuf,
            1.0,
            -128.0,
            vImage_Flags(kvImageNoFlags)
        )

        let count = vDSP_Length(w * h)
        let fPtr = fBuf.data.assumingMemoryBound(to: Float.self)

        // Abs
        vDSP_vabs(fPtr, 1, fPtr, 1, count)

        // Multiply by chroma gain
        var g = Float(chromaGain)
        vDSP_vsmul(fPtr, 1, &g, fPtr, 1, count)

        // Multiply by preFilterGain
        var pf = Float(pfGain)
        vDSP_vsmul(fPtr, 1, &pf, fPtr, 1, count)

        // Clip to [0, 255]
        var minVal: Float = 0
        var maxVal: Float = 255
        vDSP_vclip(fPtr, 1, &minVal, &maxVal, fPtr, 1, count)

        // Convert back to Planar8
        let outRowBytes = w
        let outByteCount = outRowBytes * h

        guard let outData = malloc(outByteCount) else {
            free(fData)
            return nil
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