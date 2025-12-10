import Foundation
import Metal
import CoreVideo

final class YCompute {

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

        p_extract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_extract")!)
        p_min = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_min")!)
        p_max = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_max")!)
        p_norm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_norm")!)
        p_edge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_edge")!)
        p_crop = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_y")!)
        p_sr = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_y")!)
    }

    func extractY(from pb: CVPixelBuffer,
                  into texY: MTLTexture,
                  cb: MTLCommandBuffer)
    {
        let w = texY.width
        let h = texY.height

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
                                                  0,
                                                  &srcTexRef)
        guard let metalTex = srcTexRef.flatMap({ CVMetalTextureGetTexture($0) }) else { return }

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_extract)
        enc.setTexture(metalTex, index: 0)
        enc.setTexture(texY, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func cropY(from texY: MTLTexture,
               into texYRoi: MTLTexture,
               roiX: Int,
               roiY: Int,
               cb: MTLCommandBuffer)
    {
        var ox = UInt32(roiX)
        var oy = UInt32(roiY)

        let w = texYRoi.width
        let h = texYRoi.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_crop)
        enc.setTexture(texY, index: 0)
        enc.setTexture(texYRoi, index: 1)
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

    func reduceMinMax(of texYRoi: MTLTexture,
                      minTex: MTLTexture,
                      maxTex: MTLTexture,
                      cb: MTLCommandBuffer)
    {
        let w = texYRoi.width
        let h = texYRoi.height

        let enc1 = cb.makeComputeCommandEncoder()!
        enc1.setComputePipelineState(p_min)
        enc1.setTexture(texYRoi, index: 0)
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
        enc2.setTexture(texYRoi, index: 0)
        enc2.setTexture(maxTex, index: 1)
        enc2.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc2.endEncoding()
    }

    func normalizeY(roi texYRoi: MTLTexture,
                    into texYNorm: MTLTexture,
                    minTex: MTLTexture,
                    maxTex: MTLTexture,
                    cb: MTLCommandBuffer)
    {
        let w = texYRoi.width
        let h = texYRoi.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_norm)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYNorm, index: 1)
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

    func edgeY(norm texYNorm: MTLTexture,
               into texYEdge: MTLTexture,
               cb: MTLCommandBuffer)
    {
        let w = texYNorm.width
        let h = texYNorm.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_edge)
        enc.setTexture(texYNorm, index: 0)
        enc.setTexture(texYEdge, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15) / 16,
                    height: (h + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func upscaleY(from texYRoi: MTLTexture,
                  into texYSR: MTLTexture,
                  scale: Float,
                  cb: MTLCommandBuffer)
    {
        let w = texYSR.width
        let h = texYSR.height

        var s = scale

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_sr)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYSR, index: 1)
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