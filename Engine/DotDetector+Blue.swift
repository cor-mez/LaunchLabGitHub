// File: Engine/DotDetector+Blue.swift
//
//  DotDetector+Blue.swift
//  LaunchLab
//
//  Blue-channel normalization module for DotDetector.
//  Converts a half-resolution Cb ROI into a full-resolution, contrast-
//  amplified Planar8 ROI suitable for FAST9 detection.
//
//  Steps:
//   1. Convert Cb (Planar8) → PlanarF centered at 0 (Cb-128)
//   2. Take abs()
//   3. Multiply by chroma gain
//   4. Multiply by preFilterGain
//   5. Clip to [0,255]
//   6. Convert PlanarF → Planar8
//
//  All buffers allocated here must be freed by the DotDetector orchestrator.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

extension DotDetector {

    /// Normalize Cb ROI (half-res) into a full-resolution Planar8 ROI
    /// ready for SR and FAST9.
    ///
    /// - Parameters:
    ///   - cbROI: half-resolution Cb plane crop (Planar8).
    ///   - roiFullRect: original full-frame ROI (not used directly here,
    ///                  but needed for consistency with orchestrator).
    ///
    /// - Returns:
    ///   A new vImage_Buffer containing the normalized Planar8 ROI,
    ///   or nil if blue path cannot proceed (or should fallback to Y).
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

        // --- STEP 1: Allocate float buffer (PlanarF) and convert Cb→float, center at zero. ---

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

        // Convert Planar8 → PlanarF with an offset of -128 (centers around 0).
        vImageConvert_Planar8toPlanarF(
            &cbROI,
            &fBuf,
            1.0,
            -128.0,
            vImage_Flags(kvImageNoFlags)
        )

        let count = vDSP_Length(w * h)
        let fPtr = fBuf.data.assumingMemoryBound(to: Float.self)

        // --- STEP 2: abs() in place.
        vDSP_vabs(fPtr, 1, fPtr, 1, count)

        // --- STEP 3: multiply by chromaGain
        var g = Float(chromaGain)
        vDSP_vsmul(fPtr, 1, &g, fPtr, 1, count)

        // --- STEP 4: apply preFilterGain
        var pf = Float(pfGain)
        vDSP_vsmul(fPtr, 1, &pf, fPtr, 1, count)

        // --- STEP 5: clip to [0, 255]
        var minVal: Float = 0
        var maxVal: Float = 255
        vDSP_vclip(fPtr, 1, &minVal, &maxVal, fPtr, 1, count)

        // --- STEP 6: Convert PlanarF → Planar8
        let out8RowBytes = w
        let out8ByteCount = out8RowBytes * h

        guard let out8Data = malloc(out8ByteCount) else {
            free(fData)
            return nil
        }

        var out8Buf = vImage_Buffer(
            data: out8Data,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: out8RowBytes
        )

        vImageConvert_PlanarFtoPlanar8(
            &fBuf,
            &out8Buf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        // All intermediate memory (fData) is freed here; caller frees out8Data.
        free(fData)

        return out8Buf
    }
}
