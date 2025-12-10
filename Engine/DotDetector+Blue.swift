//
//  DotDetector+Blue.swift
//  LaunchLab
//

import Foundation
import Accelerate
import CoreGraphics
import CoreVideo

extension DotDetector {

    // MARK: - Entry point used by DebugFAST9 wrapper
    internal func buildBlueEnhancedROI(
        cbROI inBuf: inout vImage_Buffer
    ) -> vImage_Buffer? {

        guard config.useBlueChannel else { return nil }

        switch config.blueEnhancement {

        case .off:
            return nil

        case .boxBlur:
            return buildBlue_BoxBlur(&inBuf)

        case .bilateral:
            return buildBlue_Bilateral(&inBuf)
        }
    }

    // ---------------------------------------------------------
    // MARK: BOX BLUR PATH
    // ---------------------------------------------------------

    private func buildBlue_BoxBlur(_ cbROI: inout vImage_Buffer) -> vImage_Buffer? {

        // 1) Adaptive normalize OR fixed fallback
        guard var base = normalizeBlueAdaptive(cbROI: &cbROI)
            ?? normalizeBlueFixed(cbROI: &cbROI)
        else {
            return nil
        }

        let w = Int(base.width)
        let h = Int(base.height)
        let outBytes = w * h

        guard let outData = malloc(outBytes) else {
            return base
        }

        var dst = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )

        var src = base

        // ⭐ Modern vImage API requires backgroundColor: Pixel_8 (UInt8)
        let bg: Pixel_8 = 0   // black background for edge extension

        let err = vImageBoxConvolve_Planar8(
            &src,
            &dst,
            nil,      // temp buffer: nil allowed
            0, 0,     // ROI offsets
            3, 3,     // kernel size
            bg,       // ★ UInt8, NOT a pointer
            vImage_Flags(kvImageEdgeExtend)
        )

        if err != kvImageNoError {
            free(outData)
            return base
        }

        return dst
    }

    // ---------------------------------------------------------
    // MARK: BILATERAL PATH
    // ---------------------------------------------------------

    private func buildBlue_Bilateral(_ cbROI: inout vImage_Buffer) -> vImage_Buffer? {

        // 1) Adaptive normalize OR fixed fallback
        guard var norm = normalizeBlueAdaptive(cbROI: &cbROI) ??
                          normalizeBlueFixed(cbROI: &cbROI)
        else { return nil }

        // 2) Bilateral via Metal (Batch 1)
        let bilateral = MetalBilateralFilter()
        guard let out = bilateral.apply(norm) else {
            return norm
        }

        return out    // caller frees
    }

    // ---------------------------------------------------------
    // MARK: FIXED NORMALIZATION
    // ---------------------------------------------------------
    internal func normalizeBlueFixed(cbROI: inout vImage_Buffer) -> vImage_Buffer? {
        let w = Int(cbROI.width)
        let h = Int(cbROI.height)
        guard w >= 4, h >= 4 else { return nil }

        let count = vDSP_Length(w * h)
        let floatBytes = w * h * MemoryLayout<Float>.stride

        guard let fData = malloc(floatBytes) else { return nil }
        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * MemoryLayout<Float>.stride
        )

        vImageConvert_Planar8toPlanarF(&cbROI, &fBuf, 1.0, -128.0, 0)
        let ptr = fBuf.data.assumingMemoryBound(to: Float.self)

        // abs(Cb-128)
        vDSP_vabs(ptr, 1, ptr, 1, count)

        // conservative gains
        var cg = max(0.5, min(config.blueChromaGain, 2.0))
        var pg = max(0.5, min(config.preFilterGain, 1.5))
        vDSP_vsmul(ptr, 1, &cg, ptr, 1, count)
        vDSP_vsmul(ptr, 1, &pg, ptr, 1, count)

        var lo: Float = 0, hi: Float = 255
        vDSP_vclip(ptr, 1, &lo, &hi, ptr, 1, count)

        // convert to Planar8
        let rowBytes = w
        let outBytes = rowBytes * h
        guard let outData = malloc(outBytes) else {
            free(fData)
            return nil
        }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rowBytes
        )

        vImageConvert_PlanarFtoPlanar8(&fBuf, &outBuf, 1.0, 0, 0)
        free(fData)
        return outBuf
    }

    // ---------------------------------------------------------
    // MARK: ADAPTIVE NORMALIZATION
    // ---------------------------------------------------------
    internal func normalizeBlueAdaptive(cbROI: inout vImage_Buffer) -> vImage_Buffer? {

        let w = Int(cbROI.width)
        let h = Int(cbROI.height)
        guard w >= 4, h >= 4 else { return nil }

        let count = vDSP_Length(w * h)
        let floatBytes = w * h * MemoryLayout<Float>.stride

        guard let fData = malloc(floatBytes) else { return nil }
        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * MemoryLayout<Float>.stride
        )

        vImageConvert_Planar8toPlanarF(&cbROI, &fBuf, 1.0, -128.0, 0)
        let ptr = fBuf.data.assumingMemoryBound(to: Float.self)

        // abs(Cb-128)
        vDSP_vabs(ptr, 1, ptr, 1, count)

        // peak deviation
        var maxVal: Float = 0
        vDSP_maxv(ptr, 1, &maxVal, count)

        // If chroma is extremely weak, return nil so Y-path handles it
        if maxVal < 5 {
            free(fData)
            return nil
        }

        // ⬇️ Tone down aggressive scaling
        let effectiveMax = max(maxVal, 40)        // don't overboost noise
        let targetMax: Float = 120               // < 255 to preserve headroom
        var scale = targetMax / effectiveMax
        vDSP_vsmul(ptr, 1, &scale, ptr, 1, count)

        var lo: Float = 0
        var hi: Float = 255
        vDSP_vclip(ptr, 1, &lo, &hi, ptr, 1, count)

        let rowBytes = w
        let outBytes = rowBytes * h
        guard let outData = malloc(outBytes) else {
            free(fData)
            return nil
        }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rowBytes
        )

        vImageConvert_PlanarFtoPlanar8(&fBuf, &outBuf, 1.0, 0, 0)
        free(fData)
        return outBuf
    }
}
