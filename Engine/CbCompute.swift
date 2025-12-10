import Foundation
import Metal
import CoreVideo

final class CbCompute {

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    let p_extract: MTLComputePipelineState
    let p_min: MTLComputePipelineState
    let p_max: MTLComputePipelineState
    let p_norm: MTLComputePipelineState
    let p_edge: MTLComputePipelineState
    let p_crop: MTLComputePipelineState
    let p_sr: MTLComputePipelineState

    init(device: MTLDevice,
         queue: MTLCommandQueue,
         library: MTLLibrary)
    {
        self.device = device
        self.queue = queue
        self.library = library

        p_extract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_extract")!)
        p_min = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_min")!)
        p_max = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_max")!)
        p_norm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_norm")!)
        p_edge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_edge")!)
        p_crop = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_cb")!)
        p_sr = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_cb")!)
    }

    func extractCb(from pb: CVPixelBuffer,
                   into texCb: MTLTexture,
                   cb: MTLCommandBuffer)
    {
        let w = texCb.width
        let h = texCb.height

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &tmp)
        var srcTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil,
                                                  tmp!,
                                                  pb,
                                                  nil,
                                                  .r8Unorm,
                                                  w,
                                                  h,
                                                  1,
                                                  &srcTexRef)
        guard let metalTex = srcTexRef.flatMap({ CVMetalTextureGetTexture($0) }) else { return }

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_extract)
        enc.setTexture(metalTex, index: 0)
        enc.setTexture(texCb, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func cropCb(from texCb: MTLTexture,
                into texCbRoi: MTLTexture,
                roiX: Int,
                roiY: Int,
                cb: MTLCommandBuffer)
    {
        var ox = UInt32(roiX)
        var oy = UInt32(roiY)

        let w = texCbRoi.width
        let h = texCbRoi.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_crop)
        enc.setTexture(texCb, index: 0)
        enc.setTexture(texCbRoi, index: 1)
        enc.setBytes(&ox, length: 4, index: 0)
        enc.setBytes(&oy, length: 4, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func reduceMinMax(of texCbRoi: MTLTexture,
                      minTex: MTLTexture,
                      maxTex: MTLTexture,
                      cb: MTLCommandBuffer)
    {
        let w = texCbRoi.width
        let h = texCbRoi.height

        let enc1 = cb.makeComputeCommandEncoder()!
        enc1.setComputePipelineState(p_min)
        enc1.setTexture(texCbRoi, index: 0)
        enc1.setTexture(minTex, index: 1)
        enc1.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc1.endEncoding()

        let enc2 = cb.makeComputeCommandEncoder()!
        enc2.setComputePipelineState(p_max)
        enc2.setTexture(texCbRoi, index: 0)
        enc2.setTexture(maxTex, index: 1)
        enc2.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc2.endEncoding()
    }

    func normalizeCb(roi texCbRoi: MTLTexture,
                     into texCbNorm: MTLTexture,
                     minTex: MTLTexture,
                     maxTex: MTLTexture,
                     cb: MTLCommandBuffer)
    {
        let w = texCbRoi.width
        let h = texCbRoi.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_norm)
        enc.setTexture(texCbRoi, index: 0)
        enc.setTexture(texCbNorm, index: 1)
        enc.setTexture(minTex, index: 2)
        enc.setTexture(maxTex, index: 3)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func edgeCb(norm texCbNorm: MTLTexture,
                into texCbEdge: MTLTexture,
                cb: MTLCommandBuffer)
    {
        let w = texCbNorm.width
        let h = texCbNorm.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_edge)
        enc.setTexture(texCbNorm, index: 0)
        enc.setTexture(texCbEdge, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func upscaleCb(from texCbRoi: MTLTexture,
                   into texCbSR: MTLTexture,
                   scale: Float,
                   cb: MTLCommandBuffer)
    {
        let w = texCbSR.width
        let h = texCbSR.height

        var s = scale

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_sr)
        enc.setTexture(texCbRoi, index: 0)
        enc.setTexture(texCbSR, index: 1)
        enc.setBytes(&s, length: 4, index: 0)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }
}
