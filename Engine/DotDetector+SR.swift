// File: Engine/DotDetector+SR.swift
//
//  Super-Resolution (SR) module for DotDetector.
//

import Foundation
import CoreGraphics
import Accelerate

extension DotDetector {

    func applySR(
        roiBuffer: vImage_Buffer,
        roiRect: CGRect
    ) -> (buffer: vImage_Buffer, scale: Float) {

        let w = Int(roiBuffer.width)
        let h = Int(roiBuffer.height)

        guard w >= 8, h >= 8 else {
            return (roiBuffer, 1.0)
        }

        if let override = config.srScaleOverride {
            let s = max(1.0, min(3.0, override))
            if s == 1.0 || config.useSuperResolution == false {
                return (roiBuffer, 1.0)
            }
            return upscale(buffer: roiBuffer, scale: s)
        }

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

        return upscale(buffer: roiBuffer, scale: autoScale)
    }

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

        guard let outData = malloc(outByteCount) else {
            return (buffer, 1.0)
        }

        var dstBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(scaledH),
            width: vImagePixelCount(scaledW),
            rowBytes: outRowBytes
        )

        var srcBuf = buffer

        let err = vImageScale_Planar8(
            &srcBuf,
            &dstBuf,
            nil,
            vImage_Flags(kvImageHighQualityResampling | kvImageEdgeExtend)
        )

        if err != kvImageNoError {
            free(outData)
            return (buffer, 1.0)
        }

        return (dstBuf, scale)
    }
}