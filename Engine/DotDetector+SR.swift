//
//  DotDetector+SR.swift
//  LaunchLab
//
//  Super-resolution scaling for DotDetector.
//  Applies vImageScale_Planar8 with HQ resampling.
//  Returns (scaledBuffer, scaleUsed).
//

import Foundation
import Accelerate
import CoreGraphics

extension DotDetector {

    /// Apply super-resolution scaling to the ROI buffer.
    ///
    /// - Parameters:
    ///   - roiBuffer: 8-bit Planar8 vImage buffer.
    ///   - roiRect: Full-frame ROI coordinates (not directly used).
    ///
    /// - Returns:
    ///   (scaledBuffer, scale) — where scale == 1.0 indicates fallback/no SR.
    ///
    internal func applySR(
        roiBuffer: vImage_Buffer,
        roiRect: CGRect
    ) -> (vImage_Buffer, Float) {

        let w = Int(roiBuffer.width)
        let h = Int(roiBuffer.height)

        // Reject pathological small ROI
        guard w >= 8, h >= 8 else {
            return (roiBuffer, 1.0)
        }

        // SR disabled
        guard config.useSuperResolution else {
            return (roiBuffer, 1.0)
        }

        // 1. Explicit override always wins
        if let override = config.srScaleOverride {
            let s = max(1.0, min(3.0, override))
            if s == 1.0 { return (roiBuffer, 1.0) }
            return upscale(buffer: roiBuffer, scale: s)
        }

        // 2. Auto-scale selection
        let minDim = min(w, h)
        let autoScale: Float

        if minDim < 100 { autoScale = 3.0 }
        else if minDim < 180 { autoScale = 2.0 }
        else { autoScale = 1.5 }

        if autoScale <= 1.0 {
            return (roiBuffer, 1.0)
        }

        // Perform actual upscaling
        return upscale(buffer: roiBuffer, scale: autoScale)
    }

    // MARK: - Private upscaling helper

    /// Upscale a Planar8 vImage buffer by the given scale.
    /// Returns (scaledBuf, actualScale), or (original,1.0) on failure.
    private func upscale(
        buffer: vImage_Buffer,
        scale: Float
    ) -> (vImage_Buffer, Float) {

        let w = Int(buffer.width)
        let h = Int(buffer.height)

        let scaledW = max(8, Int(Float(w) * scale))
        let scaledH = max(8, Int(Float(h) * scale))

        let outRB = scaledW
        let outBytes = scaledW * scaledH

        guard let outData = malloc(outBytes) else {
            return (buffer, 1.0)
        }

        var src = buffer
        var dst = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(scaledH),
            width: vImagePixelCount(scaledW),
            rowBytes: outRB
        )

        let err = vImageScale_Planar8(
            &src,
            &dst,
            nil,
            vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend)
        )

        guard err == kvImageNoError else {
            free(outData)
            return (buffer, 1.0)
        }

        return (dst, scale)
    }
}
