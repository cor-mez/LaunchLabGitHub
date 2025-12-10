import Foundation
import Metal

final class Fast9Compute {

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    let p_fast9: MTLComputePipelineState
    let p_score: MTLComputePipelineState

    init(device: MTLDevice,
         queue: MTLCommandQueue,
         library: MTLLibrary)
    {
        self.device = device
        self.queue = queue
        self.library = library

        p_fast9 = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_gpu")!)
        p_score = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_score_gpu")!)
    }

    func detectCorners(from src: MTLTexture,
                       into dst: MTLTexture,
                       threshold: Int,
                       cb: MTLCommandBuffer)
    {
        var t = threshold
        let w = src.width
        let h = src.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_fast9)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&t, length: 4, index: 0)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15)/16, height: (h + 15)/16, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func scoreCorners(from src: MTLTexture,
                      into dst: MTLTexture,
                      threshold: Int,
                      cb: MTLCommandBuffer)
    {
        var t = threshold
        let w = src.width
        let h = src.height

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(p_score)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&t, length: 4, index: 0)
        enc.dispatchThreadgroups(
            MTLSize(width: (w + 15)/16, height: (h + 15)/16, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func readBinaryFast9(from tex: MTLTexture,
                         into buffer: UnsafeMutablePointer<UInt8>)
    {
        let w = tex.width
        let h = tex.height
        let region = MTLRegionMake2D(0, 0, w, h)
        tex.getBytes(buffer, bytesPerRow: w, from: region, mipmapLevel: 0)
    }

    func readScoreFast9(from tex: MTLTexture,
                        into buffer: UnsafeMutablePointer<Float>)
    {
        let w = tex.width
        let h = tex.height
        var tmp = [UInt8](repeating: 0, count: w*h)
        let region = MTLRegionMake2D(0, 0, w, h)
        tex.getBytes(&tmp, bytesPerRow: w, from: region, mipmapLevel: 0)
        for i in 0..<tmp.count { buffer[i] = Float(tmp[i]) }
    }
}   