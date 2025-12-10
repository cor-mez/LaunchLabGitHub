//
// DotDetector+ROI.swift
//

import Foundation
import CoreVideo
import Accelerate

extension DotDetector {

    public struct ROICropResult {
        public let yROI: vImage_Buffer
        public let cbROI: vImage_Buffer?
        public let roiRect: CGRect
    }

    internal func cropROI(
        pixelBuffer: CVPixelBuffer,
        roiFullRect: CGRect
    ) -> ROICropResult {

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        // Clamp
        let roi = roiFullRect.intersection(
            CGRect(x: 0, y: 0, width: w, height: h)
        )

        let x0 = Int(roi.minX)
        let y0 = Int(roi.minY)
        let rw = Int(roi.width)
        let rh = Int(roi.height)

        // ------------------------
        // Y PLANE
        // ------------------------
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
        let yRB   = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yPtr  = yBase.assumingMemoryBound(to: UInt8.self)

        let outY = malloc(rw * rh)!
        let outYPtr = outY.assumingMemoryBound(to: UInt8.self)

        for row in 0..<rh {
            let src = yPtr + (y0 + row)*yRB + x0
            memcpy(outYPtr + row*rw, src, rw)
        }

        var yBuf = vImage_Buffer(
            data: outY,
            height: vImagePixelCount(rh),
            width: vImagePixelCount(rw),
            rowBytes: rw
        )

        // ------------------------
        // CB PLANE (half res)
        // ------------------------
        let cbW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let cbH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let cbRB = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let cbBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
        let cbPtr  = cbBase.assumingMemoryBound(to: UInt8.self)

        // Map ROI from full-res to half-res
        let sx0 = x0 / 2
        let sy0 = y0 / 2
        let srw = rw / 2
        let srh = rh / 2

        var cbBufOpt: vImage_Buffer? = nil
        if srw > 0, srh > 0 {
            let outCB = malloc(srw * srh)!
            let outCBPtr = outCB.assumingMemoryBound(to: UInt8.self)

            for row in 0..<srh {
                let src = cbPtr + (sy0 + row)*cbRB + sx0*2
                let dst = outCBPtr + row*srw
                for x in 0..<srw {
                    dst[x] = src[x*2]   // Cb only
                }
            }

            cbBufOpt = vImage_Buffer(
                data: outCB,
                height: vImagePixelCount(srh),
                width: vImagePixelCount(srw),
                rowBytes: srw
            )
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        return ROICropResult(
            yROI: yBuf,
            cbROI: cbBufOpt,
            roiRect: roi
        )
    }
}
