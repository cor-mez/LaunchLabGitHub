// File: Engine/DotDetector+ROI.swift
//
//  ROI crop module for DotDetector.
//  - Extracts a tight Planar8 Y-plane ROI from a CVPixelBuffer.
//  - Optionally extracts a half-resolution Planar8 Cb-plane ROI
//    for Blue-first paths (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange).
//  - Performs robust ROI clamping and minimum-size enforcement.
//  - Ownership of all allocated buffers is transferred to the caller,
//    which is responsible for freeing yROI.data and cbROI?.data.
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

extension DotDetector {

    public struct ROICropResult {
        public let yROI: vImage_Buffer         // Always present (Planar8)
        public let cbROI: vImage_Buffer?       // Present only in Blue mode
        public let roiRect: CGRect             // Full-frame coordinates used
    }

    /// Crops a tight Y-plane ROI and optional Cb-plane ROI from the given pixel buffer.
    ///
    /// - Parameters:
    ///   - pixelBuffer: BiPlanar YUV420 buffer (full-range).
    ///   - roiFullRect: Desired ROI in full-frame pixel coordinates (or nil for full frame).
    ///
    /// - Returns: ROICropResult with allocated vImage_Buffers and the actual clamped ROI.
    ///            Caller must free yROI.data and cbROI?.data when done.
    public func cropROI(
        pixelBuffer: CVPixelBuffer,
        roiFullRect: CGRect?
    ) -> ROICropResult {

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)

        let fullRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(frameWidth),
            height: CGFloat(frameHeight)
        )

        // 1) Resolve and clamp ROI to full frame.
        var roi = roiFullRect ?? fullRect
        roi = roi.intersection(fullRect)

        // If ROI is empty/null, use full frame.
        if roi.isNull || roi.isEmpty {
            roi = fullRect
        }

        // 2) Enforce minimum size (8×8) and clamp again.
        let minSize: CGFloat = 8.0

        var x0 = Int(floor(roi.origin.x))
        var y0 = Int(floor(roi.origin.y))
        var x1 = Int(ceil(roi.maxX))
        var y1 = Int(ceil(roi.maxY))

        if x1 - x0 < Int(minSize) {
            let cx = (x0 + x1) / 2
            let half = Int(minSize / 2.0)
            x0 = cx - half
            x1 = cx + half
        }

        if y1 - y0 < Int(minSize) {
            let cy = (y0 + y1) / 2
            let half = Int(minSize / 2.0)
            y0 = cy - half
            y1 = cy + half
        }

        x0 = max(0, x0)
        y0 = max(0, y0)
        x1 = min(frameWidth, x1)
        y1 = min(frameHeight, y1)

        let roiW = max(8, x1 - x0)
        let roiH = max(8, y1 - y0)

        let finalROI = CGRect(
            x: CGFloat(x0),
            y: CGFloat(y0),
            width: CGFloat(roiW),
            height: CGFloat(roiH)
        )

        // 3) Y-plane crop (always present).
        let yPlaneIndex = 0
        let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, yPlaneIndex)

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, yPlaneIndex) else {
            // Fallback: zero-filled ROI if base address is unavailable.
            let yByteCount = roiW * roiH
            let yData = calloc(yByteCount, MemoryLayout<UInt8>.stride) ?? UnsafeMutableRawPointer(bitPattern: 0)!
            var yBuf = vImage_Buffer(
                data: yData,
                height: vImagePixelCount(roiH),
                width: vImagePixelCount(roiW),
                rowBytes: roiW
            )
            return ROICropResult(
                yROI: yBuf,
                cbROI: nil,
                roiRect: finalROI
            )
        }

        let ySrcPtr = yBase.assumingMemoryBound(to: UInt8.self)
        let yRowBytesDst = roiW
        let yByteCountDst = yRowBytesDst * roiH

        guard let yData = malloc(yByteCountDst) else {
            // As a last resort, return a zero-filled ROI.
            let fallbackData = calloc(yByteCountDst, MemoryLayout<UInt8>.stride) ?? UnsafeMutableRawPointer(bitPattern: 0)!
            var yBuf = vImage_Buffer(
                data: fallbackData,
                height: vImagePixelCount(roiH),
                width: vImagePixelCount(roiW),
                rowBytes: yRowBytesDst
            )
            return ROICropResult(
                yROI: yBuf,
                cbROI: nil,
                roiRect: finalROI
            )
        }

        let yDstPtr = yData.assumingMemoryBound(to: UInt8.self)

        for row in 0..<roiH {
            let srcRowPtr = ySrcPtr.advanced(by: (y0 + row) * yRowBytes + x0)
            let dstRowPtr = yDstPtr.advanced(by: row * yRowBytesDst)
            memcpy(dstRowPtr, srcRowPtr, roiW)
        }

        var yBuf = vImage_Buffer(
            data: yData,
            height: vImagePixelCount(roiH),
            width: vImagePixelCount(roiW),
            rowBytes: yRowBytesDst
        )

        // 4) Optional Cb-plane crop (Blue path only).
        //    This does NOT normalize chroma or rescale to full-res; it only extracts half-res Cb.

        var cbBufOpt: vImage_Buffer? = nil

        if config.useBlueChannel {
            let chromaPlaneIndex = 1
            let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, chromaPlaneIndex)
            let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, chromaPlaneIndex)
            let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, chromaPlaneIndex)

            if chromaWidth > 0,
               chromaHeight > 0,
               let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, chromaPlaneIndex) {

                // Map full-res ROI into half-res chroma coordinates (assuming 2×2 subsampling).
                let scaleX = Double(chromaWidth) / Double(frameWidth)
                let scaleY = Double(chromaHeight) / Double(frameHeight)

                let cbX0 = max(0, Int(floor(Double(x0) * scaleX)))
                let cbY0 = max(0, Int(floor(Double(y0) * scaleY)))
                let cbX1 = min(chromaWidth, Int(ceil(Double(x1) * scaleX)))
                let cbY1 = min(chromaHeight, Int(ceil(Double(y1) * scaleY)))

                let cbW = max(4, cbX1 - cbX0)
                let cbH = max(4, cbY1 - cbY0)

                let cbRowBytesDst = cbW
                let cbByteCountDst = cbRowBytesDst * cbH

                if let cbData = malloc(cbByteCountDst) {
                    let chromaPtr = chromaBase.assumingMemoryBound(to: UInt8.self)
                    let cbDstPtr = cbData.assumingMemoryBound(to: UInt8.self)

                    // Extract Cb only (even indices in UVUV interleaved plane).
                    for row in 0..<cbH {
                        let srcRowPtr = chromaPtr.advanced(by: (cbY0 + row) * chromaRowBytes)
                        let dstRowPtr = cbDstPtr.advanced(by: row * cbRowBytesDst)
                        for x in 0..<cbW {
                            dstRowPtr[x] = srcRowPtr[(cbX0 + x) * 2]
                        }
                    }

                    cbBufOpt = vImage_Buffer(
                        data: cbData,
                        height: vImagePixelCount(cbH),
                        width: vImagePixelCount(cbW),
                        rowBytes: cbRowBytesDst
                    )
                }
            }
        }

        return ROICropResult(
            yROI: yBuf,
            cbROI: cbBufOpt,
            roiRect: finalROI
        )
    }
}