// YCompute.swift

import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

final class YCompute {

    static let shared = YCompute()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let cache: CVMetalTextureCache
    let library: MTLLibrary

    let quad: MTLBuffer
    let samplerNearest: MTLSamplerState

    let kYExtract: MTLComputePipelineState
    let kYMin: MTLComputePipelineState
    let kYMax: MTLComputePipelineState
    let kYNorm: MTLComputePipelineState
    let kYEdge: MTLComputePipelineState
    let kRoiCrop: MTLComputePipelineState
    let kSRNearest: MTLComputePipelineState

    var texY: MTLTexture?
    var texYNorm: MTLTexture?
    var texYEdge: MTLTexture?
    var texYRoi: MTLTexture?
    var texYRoiSR: MTLTexture?

    private var frameW: Int = 0
    private var frameH: Int = 0
    private var roiW: Int = 0
    private var roiH: Int = 0
    private var srW: Int = 0
    private var srH: Int = 0

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!

        var tc: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &tc)
        cache = tc!

        library = device.makeDefaultLibrary()!

        let quadData: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        quad = device.makeBuffer(bytes: quadData,
                                 length: quadData.count * MemoryLayout<Float>.size)!

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .nearest
        sd.magFilter = .nearest
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        samplerNearest = device.makeSamplerState(descriptor: sd)!

        kYExtract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_extract")!)
        kYMin = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_min")!)
        kYMax = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_max")!)
        kYNorm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_norm")!)
        kYEdge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_edge")!)
        kRoiCrop = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_y")!)
        kSRNearest = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_y")!)
    }
}
extension YCompute {

    func ensureFrameSize(_ w: Int, _ h: Int) {
        if frameW == w && frameH == h { return }
        frameW = w
        frameH = h
        texY = makeR8(w: w, h: h)
        texYNorm = makeR8(w: w, h: h)
        texYEdge = makeR8(w: w, h: h)
    }

    func ensureRoiSize(_ w: Int, _ h: Int) {
        if roiW == w && roiH == h { return }
        roiW = w
        roiH = h
        texYRoi = makeR8(w: w, h: h)
    }

    func ensureRoiSRSize(_ sw: Int, _ sh: Int) {
        if srW == sw && srH == sh { return }
        srW = sw
        srH = sh
        texYRoiSR = makeR8(w: sw, h: sh)
    }

    private func makeR8(w: Int, h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                         width: w,
                                                         height: h,
                                                         mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }

    func extractY(pixelBuffer: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        ensureFrameSize(w, h)

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil,
                                                  cache,
                                                  pixelBuffer,
                                                  nil,
                                                  .r8Unorm,
                                                  w,
                                                  h,
                                                  0,
                                                  &tmp)
        if let t = tmp {
            texY = CVMetalTextureGetTexture(t)
        }
    }

    func computeRoiMinMax(cb: MTLCommandBuffer) -> (MTLTexture, MTLTexture) {
        let minTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                  width: 1,
                                                                  height: 1,
                                                                  mipmapped: false)
        minTexDesc.usage = [.shaderRead, .shaderWrite]
        let minTex = device.makeTexture(descriptor: minTexDesc)!

        let maxTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                                  width: 1,
                                                                  height: 1,
                                                                  mipmapped: false)
        maxTexDesc.usage = [.shaderRead, .shaderWrite]
        let maxTex = device.makeTexture(descriptor: maxTexDesc)!

        let enc1 = cb.makeComputeCommandEncoder()!
        enc1.setComputePipelineState(kYMin)
        enc1.setTexture(texYRoi, index: 0)
        enc1.setTexture(minTex, index: 1)
        enc1.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                  threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc1.endEncoding()

        let enc2 = cb.makeComputeCommandEncoder()!
        enc2.setComputePipelineState(kYMax)
        enc2.setTexture(texYRoi, index: 0)
        enc2.setTexture(maxTex, index: 1)
        enc2.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                  threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc2.endEncoding()

        return (minTex, maxTex)
    }

    func normalizeRoi(cb: MTLCommandBuffer,
                      minTex: MTLTexture,
                      maxTex: MTLTexture)
    {
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kYNorm)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYRoi, index: 1)
        enc.setTexture(minTex, index: 2)
        enc.setTexture(maxTex, index: 3)
        enc.dispatchThreadgroups(
            MTLSize(width: (roiW + 15) / 16,
                    height: (roiH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func edgeRoi(cb: MTLCommandBuffer) {
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kYEdge)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYRoi, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (roiW + 15) / 16,
                    height: (roiH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }
}
extension YCompute {

    func cropRoi(cb: MTLCommandBuffer, roi: CGRect) {
        let x = Int(roi.origin.x)
        let y = Int(roi.origin.y)
        var ox = UInt32(x)
        var oy = UInt32(y)

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kRoiCrop)
        enc.setTexture(texY, index: 0)
        enc.setTexture(texYRoi, index: 1)
        enc.setBytes(&ox, length: 4, index: 0)
        enc.setBytes(&oy, length: 4, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (roiW + 15) / 16,
                    height: (roiH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func upscaleRoi(cb: MTLCommandBuffer, scale: Float) {
        var s = scale
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kSRNearest)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYRoiSR, index: 1)
        enc.setBytes(&s, length: 4, index: 0)
        enc.dispatchThreadgroups(
            MTLSize(width: (srW + 15) / 16,
                    height: (srH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func prepareYChain(pixelBuffer: CVPixelBuffer,
                       roi: CGRect,
                       srScale: Float)
    {
        extractY(pixelBuffer: pixelBuffer)

        let rw = Int(roi.width)
        let rh = Int(roi.height)
        ensureRoiSize(rw, rh)

        let srw = max(1, Int(Float(rw) * srScale))
        let srh = max(1, Int(Float(rh) * srScale))
        ensureRoiSRSize(srw, srh)

        let cb1 = queue.makeCommandBuffer()!
        cropRoi(cb: cb1, roi: roi)
        cb1.commit()

        let cb2 = queue.makeCommandBuffer()!
        let (minT, maxT) = computeRoiMinMax(cb: cb2)
        cb2.commit()

        let cb3 = queue.makeCommandBuffer()!
        normalizeRoi(cb: cb3, minTex: minT, maxTex: maxT)
        cb3.commit()

        let cb4 = queue.makeCommandBuffer()!
        edgeRoi(cb: cb4)
        cb4.commit()

        let cb5 = queue.makeCommandBuffer()!
        upscaleRoi(cb: cb5, scale: srScale)
        cb5.commit()
    }

    func debugYNormTexture() -> MTLTexture? {
        return texYNorm
    }

    func debugYEdgeTexture() -> MTLTexture? {
        return texYEdge
    }

    func debugYRoiTexture() -> MTLTexture? {
        return texYRoi
    }

    func debugYRoiSRTexture() -> MTLTexture? {
        return texYRoiSR
    }
}
// YCompute.swift — Segment 3

extension YCompute {

    struct Fast9Dims {
        let width: Int
        let height: Int
    }

    func fast9DimensionsY() -> Fast9Dims {
        guard let t = texFast9Y else {
            return Fast9Dims(width: 0, height: 0)
        }
        return Fast9Dims(width: t.width, height: t.height)
    }

    func readFast9Y(into buffer: UnsafeMutablePointer<UInt8>,
                    width: Int,
                    height: Int)
    {
        guard let tex = texFast9Y else { return }
        let region = MTLRegionMake2D(0, 0, width, height)
        tex.getBytes(buffer,
                     bytesPerRow: width,
                     from: region,
                     mipmapLevel: 0)
    }

    func readFast9YScore(into buffer: UnsafeMutablePointer<Float>,
                         width: Int,
                         height: Int)
    {
        guard let tex = texFast9YScore else { return }
        var tmp = [UInt8](repeating: 0, count: width * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        tex.getBytes(&tmp,
                     bytesPerRow: width,
                     from: region,
                     mipmapLevel: 0)
        for i in 0..<tmp.count {
            buffer[i] = Float(tmp[i])
        }
    }

    func debugFast9YTexture() -> MTLTexture? {
        return texFast9Y
    }

    func debugFast9YScoreTexture() -> MTLTexture? {
        return texFast9YScore
    }
}
