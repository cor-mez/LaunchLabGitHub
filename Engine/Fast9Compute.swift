// Fast9Compute.swift

import Foundation
import Metal
import MetalKit
import simd

final class Fast9Compute {

    static let shared = Fast9Compute()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    let tg: MTLSize

    let kFast9Corner: MTLComputePipelineState
    let kFast9Score: MTLComputePipelineState
    let kFast9ScoreDebug: MTLComputePipelineState

    private var texFast9: MTLTexture?
    private var texFast9Score: MTLTexture?
    private var texFast9ScoreDebug: MTLTexture?

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
        tg = MTLSize(width: 16, height: 16, depth: 1)

        kFast9Corner = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_gpu")!)
        kFast9Score = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_score_gpu")!)
        kFast9ScoreDebug = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_fast9_score_debug")!)
    }

    private func allocCornerTex(width: Int, height: Int) {
        if texFast9 == nil || texFast9!.width != width || texFast9!.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            d.usage = [.shaderRead, .shaderWrite]
            texFast9 = device.makeTexture(descriptor: d)
        }
    }

    private func allocScoreTex(width: Int, height: Int) {
        if texFast9Score == nil || texFast9Score!.width != width || texFast9Score!.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float,
                width: width,
                height: height,
                mipmapped: false
            )
            d.usage = [.shaderRead, .shaderWrite]
            texFast9Score = device.makeTexture(descriptor: d)
        }
    }

    private func allocScoreDebugTex(width: Int, height: Int) {
        if texFast9ScoreDebug == nil || texFast9ScoreDebug!.width != width || texFast9ScoreDebug!.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            d.usage = [.shaderRead, .shaderWrite]
            texFast9ScoreDebug = device.makeTexture(descriptor: d)
        }
    }
}
// Fast9Compute.swift — Segment 2

extension Fast9Compute {

    struct Fast9Dims {
        let width: Int
        let height: Int
    }

    func runFast9(
        src: MTLTexture,
        threshold: Float
    ) {
        let w = src.width
        let h = src.height

        allocCornerTex(width: w, height: h)
        allocScoreTex(width: w, height: h)
        allocScoreDebugTex(width: w, height: h)

        var thr = threshold

        let cb = queue.makeCommandBuffer()!

        let enc1 = cb.makeComputeCommandEncoder()!
        enc1.setComputePipelineState(kFast9Corner)
        enc1.setTexture(src, index: 0)
        enc1.setTexture(texFast9, index: 1)
        enc1.setBytes(&thr, length: MemoryLayout<Float>.size, index: 0)
        let ng = MTLSize(width: (w + tg.width - 1) / tg.width,
                         height: (h + tg.height - 1) / tg.height,
                         depth: 1)
        enc1.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc1.endEncoding()

        let enc2 = cb.makeComputeCommandEncoder()!
        enc2.setComputePipelineState(kFast9Score)
        enc2.setTexture(src, index: 0)
        enc2.setTexture(texFast9Score, index: 1)
        enc2.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc2.endEncoding()

        let enc3 = cb.makeComputeCommandEncoder()!
        enc3.setComputePipelineState(kFast9ScoreDebug)
        enc3.setTexture(texFast9Score, index: 0)
        enc3.setTexture(texFast9ScoreDebug, index: 1)
        enc3.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc3.endEncoding()

        cb.commit()
    }

    func fast9DimsY() -> Fast9Dims {
        guard let t = texFast9 else { return Fast9Dims(width: 0, height: 0) }
        return Fast9Dims(width: t.width, height: t.height)
    }

    func fast9DimsCb() -> Fast9Dims {
        guard let t = texFast9 else { return Fast9Dims(width: 0, height: 0) }
        return Fast9Dims(width: t.width, height: t.height)
    }

    func readFast9Y(
        into buffer: UnsafeMutablePointer<UInt8>,
        maxCount: Int,
        outW: inout Int,
        outH: inout Int
    ) {
        guard let tex = texFast9 else {
            outW = 0
            outH = 0
            return
        }
        let w = tex.width
        let h = tex.height
        outW = w
        outH = h
        let bytes = w * h
        let count = min(bytes, maxCount)
        tex.getBytes(buffer,
                     bytesPerRow: w,
                     from: MTLRegionMake2D(0, 0, w, h),
                     mipmapLevel: 0)
        if count < bytes {
            for i in count..<bytes { buffer[i] = 0 }
        }
    }

    func readFast9Cb(
        into buffer: UnsafeMutablePointer<UInt8>,
        maxCount: Int,
        outW: inout Int,
        outH: inout Int
    ) {
        guard let tex = texFast9 else {
            outW = 0
            outH = 0
            return
        }
        let w = tex.width
        let h = tex.height
        outW = w
        outH = h
        let bytes = w * h
        let count = min(bytes, maxCount)
        tex.getBytes(buffer,
                     bytesPerRow: w,
                     from: MTLRegionMake2D(0, 0, w, h),
                     mipmapLevel: 0)
        if count < bytes {
            for i in count..<bytes { buffer[i] = 0 }
        }
    }

    func readFast9YScore(
        into buffer: UnsafeMutablePointer<Float>,
        width: Int,
        height: Int
    ) {
        guard let tex = texFast9Score else { return }
        let count = width * height
        var tmp = [Float](repeating: 0, count: count)
        let region = MTLRegionMake2D(0, 0, width, height)
        tex.getBytes(&tmp,
                     bytesPerRow: width * MemoryLayout<Float>.size,
                     from: region,
                     mipmapLevel: 0)
        for i in 0..<count {
            buffer[i] = tmp[i]
        }
    }

    func readFast9CbScore(
        into buffer: UnsafeMutablePointer<Float>,
        width: Int,
        height: Int
    ) {
        guard let tex = texFast9Score else { return }
        let count = width * height
        var tmp = [Float](repeating: 0, count: count)
        let region = MTLRegionMake2D(0, 0, width, height)
        tex.getBytes(&tmp,
                     bytesPerRow: width * MemoryLayout<Float>.size,
                     từ: region,
                     mipmapLevel: 0)
        for i in 0..<count {
            buffer[i] = tmp[i]
        }
    }

    func debugFast9Texture() -> MTLTexture? {
        return texFast9
    }

    func debugFast9ScoreTexture() -> MTLTexture? {
        return texFast9ScoreDebug
    }
}
