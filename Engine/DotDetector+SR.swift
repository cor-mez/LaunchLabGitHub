// File: Engine/DotDetector+SR.swift
//
//  DotDetector+SR.swift
//  LaunchLab
//
//  Super-Resolution (SR) module for DotDetector.
//  Upscales a Planar8 ROI buffer using vImage high-quality resampling,
//  returning a new upscaled Planar8 buffer + the scale factor used.
//
//  The caller (DotDetector orchestrator) is responsible for freeing
//  the returned vImage_Buffer.data after FAST9 completes.
//

import Foundation
import CoreGraphics
import Accelerate

extension DotDetector {

    /// Apply super-resolution to the ROI buffer (Planar8).
    ///
    /// - Parameters:
    ///   - roiBuffer: Planar8 buffer from Y or Blue module.
    ///   - roiRect: Full-frame ROI coordinates (not used directly here
    ///              but required for the orchestrator’s mapping).
    ///
    /// - Returns:
    ///   A tuple (buffer, scale) where:
    ///     - buffer: new Planar8 upscaled vImage_Buffer (malloc'd),
    ///               or the original roiBuffer if SR is disabled/fails.
    ///     - scale:  the effective scale used (1.0 if disabled/fallback).
    ///
    func applySR(
        roiBuffer: vImage_Buffer,
        roiRect: CGRect
    ) -> (buffer: vImage_Buffer, scale: Float) {

        let w = Int(roiBuffer.width)
        let h = Int(roiBuffer.height)

        // Reject absurdly small ROI.
        guard w >= 8, h >= 8 else {
            return (roiBuffer, 1.0)
        }

        // 1) Respect override if present.
        if let override = config.srScaleOverride {
            let s = max(1.0, min(3.0, override))
            if s == 1.0 || config.useSuperResolution == false {
                return (roiBuffer, 1.0)
            }
            return upscale(buffer: roiBuffer, scale: s)
        }

        // 2) Auto-select scale based on ROI size.
        guard config.useSuperResolution else {
            return (roiBuffer, 1.0)
        }

        let autoScale: Float
        if w < 100 {
            autoScale = 3.0
        } else if w < 180 {
            autoScale = 2.0
        } else {
            autoScale = 1.5
        }

        if autoScale <= 1.0 {
            return (roiBuffer, 1.0)
        }

        // 3) Perform upscale with autoScale.
        return upscale(buffer: roiBuffer, scale: autoScale)
    }

    // MARK: - Private helper

    /// Upscale a Planar8 vImage_Buffer by the given scale.
    /// Returns (scaledBuffer, scale) or the original buffer if memory/scaling fails.
    private func upscale(
        buffer: vImage_Buffer,
        scale: Float
    ) -> (buffer: vImage_Buffer, scale: Float) {

        let w = Int(buffer.width)
        let h = Int(buffer.height)
        let scaledW = max(8, Int(Float(w) * scale))
        let scaledH = max(8, Int(Float(h) * scale))

        let outRowBytes = scaledW
        let outByteCount = outRowBytes * scaledH

        // Allocate scaled buffer
        guard let outData = malloc(outByteCount) else {
            // Fallback: return input unchanged
            return (buffer, 1.0)
        }

        var dstBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(scaledH),
            width: vImagePixelCount(scaledW),
            rowBytes: outRowBytes
        )

        var srcBuf = buffer

        // vImage high-quality scaling with edge extension.
        let err = vImageScale_Planar8(
            &srcBuf,
            &dstBuf,
            nil,
            vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend)
        )

        if err != kvImageNoError {
            // Scaling failure — free buffer, fallback to original.
            free(outData)
            return (buffer, 1.0)
        }

        return (dstBuf, scale)
    }
}
