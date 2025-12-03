// File: Engine/DotDetector+Y.swift
//
//  DotDetector+Y.swift
//  LaunchLab
//
//  Y-path preprocessing module for DotDetector.
//  Responsible ONLY for preprocessing a Planar8 Y-plane ROI prior to
//  Super-Resolution and FAST9.
//
//  Pipeline:
//    1. Validate ROI size
//    2. Convert Planar8 → PlanarF
//    3. Multiply by gain
//    4. Clip to [0, 255]
//    5. Convert PlanarF → Planar8
//    6. Return NEW malloc-owned Planar8 buffer
//
//  Caller is responsible for freeing the returned buffer's data pointer.
//

import Foundation
import Accelerate

extension DotDetector {

    /// Preprocess the Y-plane ROI by applying optional preFilterGain.
    ///
    /// - Parameters:
    ///   - yROI: A Planar8 vImage_Buffer (caller-owned memory).
    ///   - gain: preFilterGain from DotDetectorConfig.
    ///
    /// - Returns:
    ///   A NEW Planar8 vImage_Buffer (malloc-owned), or the original
    ///   yROI unchanged if gain≈1.0 or if any allocation fails.
    ///
    func preprocessYROI(
        _ yROI: vImage_Buffer,
        gain: Float
    ) -> vImage_Buffer {

        let w = Int(yROI.width)
        let h = Int(yROI.height)

        // Reject invalid/small ROI: return unchanged.
        if w < 8 || h < 8 {
            return yROI
        }

        // Clamp gain to [0.5 … 2.0].
        let g = max(0.5, min(2.0, gain))

        // If gain == 1.0 (or extremely close), skip all conversion steps.
        if abs(g - 1.0) < 0.0001 {
            return yROI
        }

        // --- STEP 1: Allocate PlanarF buffer ---
        let floatRowBytes = w * MemoryLayout<Float>.stride
        let floatByteCount = floatRowBytes * h

        guard let fData = malloc(floatByteCount) else {
            // Allocation failure → return original YROI unchanged.
            return yROI
        }

        // Wrap float buffer
        var fBuf = vImage_Buffer(
            data: fData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: floatRowBytes
        )

        // --- STEP 2: Convert Planar8 → PlanarF ---
        var yCopy = yROI
        vImageConvert_Planar8toPlanarF(
            &yCopy,
            &fBuf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        // --- STEP 3: Multiply by gain in-place ---
        let count = vDSP_Length(w * h)
        let fPtr = fBuf.data.assumingMemoryBound(to: Float.self)
        var gVar = g
        vDSP_vsmul(fPtr, 1, &gVar, fPtr, 1, count)

        // --- STEP 4: Clip to [0, 255] ---
        var minVal: Float = 0.0
        var maxVal: Float = 255.0
        vDSP_vclip(fPtr, 1, &minVal, &maxVal, fPtr, 1, count)

        // --- STEP 5: Allocate output Planar8 buffer ---
        let outRowBytes = w
        let outByteCount = outRowBytes * h

        guard let outData = malloc(outByteCount) else {
            // Allocation failed: free float buffer, return original.
            free(fData)
            return yROI
        }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: outRowBytes
        )

        // --- STEP 6: Convert back to Planar8 ---
        vImageConvert_PlanarFtoPlanar8(
            &fBuf,
            &outBuf,
            1.0,
            0.0,
            vImage_Flags(kvImageNoFlags)
        )

        // Free float buffer
        free(fData)

        // Return the newly allocated Planar8 buffer
        return outBuf
    }
}
