//
//  ChromaDebugRenderer.swift
//  LaunchLab
//
//  Pure debug-only renderer for:
//    • Raw Cb-plane Metal texture (4:2:0 Planar8)
//    • Normalized Cb-plane Metal texture
//    • ROI zoom levels (1×, 2×, 3×)
//    • Optional Y-plane-to-texture fallback
//
//  Zero mutation of pipeline buffers. Fully GPU-safe.
//

import Foundation
import Accelerate
import Metal
import CoreVideo

// ----------------------------------------------------------------------------
// MARK: - ChromaDebugRenderer (Singleton)
// ----------------------------------------------------------------------------

public final class ChromaDebugRenderer {

    public static let shared = ChromaDebugRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue

    private init() {
        let ctx = MetalContext.shared
        device = ctx.device
        queue  = ctx.queue
    }

    // =========================================================================
    // MARK: - RAW Cb → Metal Texture
    // =========================================================================

    public func makeCbTexture(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int
    ) -> MTLTexture? {

        // Scale from half-res Cb → full preview size
        guard let scaled = scalePlanar8(cb, outW: fullWidth, outH: fullHeight) else {
            return nil
        }
        defer { free(scaled.data) }

        return makeTexture(fromPlanar8: scaled)
    }

    // =========================================================================
    // MARK: - NORMALIZED Cb → Metal Texture
    // =========================================================================

    public func makeNormalizedCbTexture(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int
    ) -> MTLTexture? {

        guard let normalized = makeNormalizedCbBuffer(cb) else { return nil }
        defer { free(normalized.data) }

        guard let scaled = scalePlanar8(normalized, outW: fullWidth, outH: fullHeight) else {
            return nil
        }
        defer { free(scaled.data) }

        return makeTexture(fromPlanar8: scaled)
    }

    // =========================================================================
    // MARK: - ROI Zoom Levels (1×/2×/3×)
// =========================================================================

    public func makeZoomLevels(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int,
        roi: CGRect?
    ) -> [MTLTexture]? {

        guard let roi = roi else { return nil }

        // Convert ROI from full-res Y-space → half-res Cb-space
        let roiCb = CGRect(
            x: roi.origin.x / 2.0,
            y: roi.origin.y / 2.0,
            width: roi.size.width / 2.0,
            height: roi.size.height / 2.0
        )

        guard let roi1 = cropPlanar8(cb, rect: roiCb) else { return nil }

        // Build scaled zoom levels
        let roi2 = roi1.scaled(by: 2.0)
        let roi3 = roi1.scaled(by: 3.0)

        defer {
            free(roi1.data)
            free(roi2.data)
            free(roi3.data)
        }

        let tex1 = makeTexture(fromPlanar8: roi1)
        let tex2 = makeTexture(fromPlanar8: roi2)
        let tex3 = makeTexture(fromPlanar8: roi3)

        return [tex1, tex2, tex3].compactMap { $0 }
    }

    // =========================================================================
    // MARK: - Optional Y-plane Texture (Debug Only)
    // =========================================================================

    public func makeYTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return nil
        }

        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rb = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        var src = vImage_Buffer(
            data: base,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rb
        )

        guard let outData = malloc(w * h) else { return nil }
        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )

        vImageCopyBuffer(&src, &outBuf, 1, vImage_Flags(kvImageNoFlags))

        return makeTexture(fromPlanar8: outBuf)
    }

    // =========================================================================
    // MARK: - Normalize Cb Buffer (Planar8 → Planar8)
// =========================================================================

    private func makeNormalizedCbBuffer(_ cb: vImage_Buffer) -> vImage_Buffer? {

        let w = Int(cb.width)
        let h = Int(cb.height)

        // Compute min/max manually — safe, fast, stable
        var minPixel: UInt8 = 255
        var maxPixel: UInt8 = 0

        let srcPtr = cb.data.assumingMemoryBound(to: UInt8.self)
        let rb = cb.rowBytes

        for y in 0..<h {
            let row = srcPtr + y * rb
            for x in 0..<w {
                let px = row[x]
                if px < minPixel { minPixel = px }
                if px > maxPixel { maxPixel = px }
            }
        }

        guard let outData = malloc(w * h) else { return nil }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )

        let range = max(1, Int(maxPixel) - Int(minPixel)) // avoid div by zero

        for y in 0..<h {
            let srcRow = cb.data.advanced(by: y * cb.rowBytes)
            let dstRow = outBuf.data.advanced(by: y * outBuf.rowBytes)

            for x in 0..<w {
                let raw = srcRow.load(fromByteOffset: x, as: UInt8.self)
                let norm = (Int(raw) - Int(minPixel)) * 255 / range
                dstRow.storeBytes(of: UInt8(clamping: norm), toByteOffset: x, as: UInt8.self)
            }
        }

        return outBuf
    }

    // =========================================================================
    // MARK: - Scale Planar8 (vImage)
// =========================================================================

    private func scalePlanar8(
        _ src: vImage_Buffer,
        outW: Int,
        outH: Int
    ) -> vImage_Buffer? {

        guard let outData = malloc(outW * outH) else { return nil }

        var dst = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(outH),
            width: vImagePixelCount(outW),
            rowBytes: outW   // tightly packed for Metal
        )

        var s = src
        let err = vImageScale_Planar8(&s, &dst, nil, vImage_Flags(kvImageHighQualityResampling))

        if err != kvImageNoError {
            free(outData)
            return nil
        }

        return dst
    }

    // =========================================================================
    // MARK: - Crop Planar8
// =========================================================================

    private func cropPlanar8(_ src: vImage_Buffer, rect: CGRect) -> vImage_Buffer? {

        let x0 = max(0, Int(rect.origin.x))
        let y0 = max(0, Int(rect.origin.y))
        let w  = max(1, Int(rect.size.width))
        let h  = max(1, Int(rect.size.height))

        guard x0 + w <= Int(src.width) else { return nil }
        guard y0 + h <= Int(src.height) else { return nil }

        guard let out = malloc(w * h) else { return nil }

        var dst = vImage_Buffer(
            data: out,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )

        for row in 0..<h {
            let srcLine = src.data.advanced(by: (y0 + row) * src.rowBytes + x0)
            let dstLine = out.advanced(by: row * w)
            memcpy(dstLine, srcLine, w)
        }

        return dst
    }

    // =========================================================================
    // MARK: - Build Metal Texture from Planar8
// =========================================================================

    func makeTexture(fromPlanar8 buf: vImage_Buffer) -> MTLTexture? {
        let w = Int(buf.width)
        let h = Int(buf.height)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        // Tightly-packed rowBytes = width
        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: buf.data,
            bytesPerRow: w
        )

        return tex
    }
}

// ----------------------------------------------------------------------------
// MARK: - vImage_Buffer Scaling Extension
// ----------------------------------------------------------------------------

private extension vImage_Buffer {

    func scaled(by factor: CGFloat) -> vImage_Buffer {
        let outW = max(1, Int(CGFloat(self.width)  * factor))
        let outH = max(1, Int(CGFloat(self.height) * factor))

        guard let outData = malloc(outW * outH) else {
            return vImage_Buffer(data: nil, height: 0, width: 0, rowBytes: 0)
        }

        var dst = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(outH),
            width: vImagePixelCount(outW),
            rowBytes: outW
        )

        var src = self
        vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))

        return dst
    }
}
