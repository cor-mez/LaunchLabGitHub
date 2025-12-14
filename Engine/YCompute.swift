//
//  YCompute.swift
//

import Foundation
import Metal
import CoreVideo

@MainActor
final class YCompute {

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    // Pipelines (wired from MetalRenderer)
    private let p_extract: MTLComputePipelineState
    private let p_min:     MTLComputePipelineState
    private let p_max:     MTLComputePipelineState
    private let p_norm:    MTLComputePipelineState
    private let p_edge:    MTLComputePipelineState
    private let p_crop:    MTLComputePipelineState
    private let p_sr:      MTLComputePipelineState

    init(device: MTLDevice,
         queue: MTLCommandQueue,
         library: MTLLibrary)
    {
        self.device  = device
        self.queue   = queue
        self.library = library

        p_extract = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_y_extract")!
        )
        p_min = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_y_min")!
        )
        p_max = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_y_max")!
        )
        p_norm = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_y_norm")!
        )
        p_edge = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_y_edge")!
        )
        p_crop = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_roi_crop_y")!
        )
        p_sr   = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_sr_nearest_y")!
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - EXTRACT Y-plane (R8 → half texture)
    // -------------------------------------------------------------------------
    func extractY(from pb: CVPixelBuffer,
                  into texY: MTLTexture,
                  cb: MTLCommandBuffer)
    {
        // Create view into Y-plane (not a texture cache!)
        let w = texY.width
        let h = texY.height

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            MetalRenderer.shared.textureCache,
            pb,
            nil,
            .r8Unorm,
            w,
            h,
            0,
            &tmp
        )

        guard let yRef = tmp,
              let src = CVMetalTextureGetTexture(yRef)
        else { return }

        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_extract)
        enc.setTexture(src,  index: 0)
        enc.setTexture(texY, index: 1)
        dispatch2D(enc, w: w, h: h)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - ROI CROP
    // -------------------------------------------------------------------------
    func cropY(from src: MTLTexture,
               into dst: MTLTexture,
               roiX: Int,
               roiY: Int,
               cb: MTLCommandBuffer)
    {
        var ox = UInt32(roiX)
        var oy = UInt32(roiY)

        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_crop)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&ox, length: 4, index: 0)
        enc.setBytes(&oy, length: 4, index: 1)
        dispatch2D(enc, w: dst.width, h: dst.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - REDUCE MIN/MAX
    // -------------------------------------------------------------------------
    func reduceMinMax(of roi: MTLTexture,
                      minTex: MTLTexture,
                      maxTex: MTLTexture,
                      cb: MTLCommandBuffer)
    {
        // MIN
        if let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(p_min)
            enc.setTexture(roi,    index: 0)
            enc.setTexture(minTex, index: 1)
            dispatch1x1(enc)
            enc.endEncoding()
        }

        // MAX
        if let enc = cb.makeComputeCommandEncoder() {
            enc.setComputePipelineState(p_max)
            enc.setTexture(roi,    index: 0)
            enc.setTexture(maxTex, index: 1)
            dispatch1x1(enc)
            enc.endEncoding()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - NORMALIZE ROI
    // -------------------------------------------------------------------------
    func normalizeY(roi: MTLTexture,
                    into dst: MTLTexture,
                    minTex: MTLTexture,
                    maxTex: MTLTexture,
                    cb: MTLCommandBuffer)
    {
        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_norm)
        enc.setTexture(roi,    index: 0)
        enc.setTexture(dst,    index: 1)
        enc.setTexture(minTex, index: 2)
        enc.setTexture(maxTex, index: 3)
        dispatch2D(enc, w: dst.width, h: dst.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - EDGE MAP
    // -------------------------------------------------------------------------
    func edgeY(norm: MTLTexture,
               into edge: MTLTexture,
               cb: MTLCommandBuffer)
    {
        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_edge)
        enc.setTexture(norm, index: 0)
        enc.setTexture(edge, index: 1)
        dispatch2D(enc, w: edge.width, h: edge.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - SUPER-RESOLUTION (Nearest)
    // -------------------------------------------------------------------------
    func upscaleY(from src: MTLTexture,
                  into dst: MTLTexture,
                  scale: Float,
                  cb: MTLCommandBuffer)
    {
        var k = scale

        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_sr)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&k, length: 4, index: 0)
        dispatch2D(enc, w: dst.width, h: dst.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - Dispatch Helpers
    // -------------------------------------------------------------------------
    private func dispatch2D(_ enc: MTLComputeCommandEncoder, w: Int, h: Int) {
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let ng = MTLSize(width: (w + 15) / 16,
                         height: (h + 15) / 16,
                         depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
    }

    private func dispatch1x1(_ enc: MTLComputeCommandEncoder) {
        let tg = MTLSize(width: 1, height: 1, depth: 1)
        enc.dispatchThreadgroups(tg, threadsPerThreadgroup: tg)
    }
}
