import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

final class CbCompute {

    static let shared = CbCompute()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let cache: CVMetalTextureCache
    let library: MTLLibrary

    let quad: MTLBuffer
    let samplerNearest: MTLSamplerState

    let kCbExtract: MTLComputePipelineState
    let kCbMin: MTLComputePipelineState
    let kCbMax: MTLComputePipelineState
    let kCbNorm: MTLComputePipelineState
    let kCbEdge: MTLComputePipelineState
    let kRoiCropCb: MTLComputePipelineState
    let kSRNearestCb: MTLComputePipelineState

    var texCb: MTLTexture?
    var texCbNorm: MTLTexture?
    var texCbEdge: MTLTexture?
    var texCbRoi: MTLTexture?
    var texCbRoiSR: MTLTexture?

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

        kCbExtract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_extract")!)
        kCbMin = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_min")!)
        kCbMax = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_max")!)
        kCbNorm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_norm")!)
        kCbEdge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_cb_edge")!)
        kRoiCropCb = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop_cb")!)
        kSRNearestCb = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest_cb")!)
    }
}
extension CbCompute {

    func ensureFrameSize(_ w: Int, _ h: Int) {
        if frameW == w && frameH == h { return }
        frameW = w
        frameH = h
        texCb = makeR8(w: w / 2, h: h / 2)
        texCbNorm = makeR8(w: w, h: h)
        texCbEdge = makeR8(w: w, h: h)
    }

    func ensureRoiSize(_ w: Int, _ h: Int) {
        if roiW == w && roiH == h { return }
        roiW = w
        roiH = h
        texCbRoi = makeR8(w: w / 2, h: h / 2)
    }

    func ensureRoiSRSize(_ sw: Int, _ sh: Int) {
        if srW == sw && srH == sh { return }
        srW = sw
        srH = sh
        texCbRoiSR = makeR8(w: sw, h: sh)
    }

    private func makeR8(w: Int, h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                         width: w,
                                                         height: h,
                                                         mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }

    func extractCb(pixelBuffer: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        ensureFrameSize(w, h)

        let cw = w / 2
        let ch = h / 2

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil,
                                                  cache,
                                                  pixelBuffer,
                                                  nil,
                                                  .rg8Unorm,
                                                  cw,
                                                  ch,
                                                  1,
                                                  &tmp)
        guard let chroma = tmp.flatMap({ CVMetalTextureGetTexture($0) }) else { return }

        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kCbExtract)
        enc.setTexture(chroma, index: 0)
        enc.setTexture(texCb, index: 1)
        let tw = MTLSize(width: 16, height: 16, depth: 1)
        let tg = MTLSize(width: (cw + 15) / 16, height: (ch + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(tg, threadsPerThreadgroup: tw)
        enc.endEncoding()
        cb.commit()
    }

    func computeRoiMinMax(cb: MTLCommandBuffer) -> (MTLTexture, MTLTexture) {
        let minDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                               width: 1,
                                                               height: 1,
                                                               mipmapped: false)
        minDesc.usage = [.shaderRead, .shaderWrite]
        let minTex = device.makeTexture(descriptor: minDesc)!

        let maxDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float,
                                                               width: 1,
                                                               height: 1,
                                                               mipmapped: false)
        maxDesc.usage = [.shaderRead, .shaderWrite]
        let maxTex = device.makeTexture(descriptor: maxDesc)!

        let enc1 = cb.makeComputeCommandEncoder()!
        enc1.setComputePipelineState(kCbMin)
        enc1.setTexture(texCbRoi, index: 0)
        enc1.setTexture(minTex, index: 1)
        enc1.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                  threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc1.endEncoding()

        let enc2 = cb.makeComputeCommandEncoder()!
        enc2.setComputePipelineState(kCbMax)
        enc2.setTexture(texCbRoi, index: 0)
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
        enc.setComputePipelineState(kCbNorm)
        enc.setTexture(texCbRoi, index: 0)
        enc.setTexture(texCbNorm, index: 1)
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
        enc.setComputePipelineState(kCbEdge)
        enc.setTexture(texCbNorm, index: 0)
        enc.setTexture(texCbEdge, index: 1)
        enc.dispatchThreadgroups(
            MTLSize(width: (roiW + 15) / 16,
                    height: (roiH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }
}
extension CbCompute {

    func cropRoiCb(cb: MTLCommandBuffer, roi: CGRect) {
        let x = Int(roi.origin.x)
        let y = Int(roi.origin.y)
        var ox = UInt32(x)
        var oy = UInt32(y)

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kRoiCrop)
        enc.setTexture(texCb, index: 0)
        enc.setTexture(texCbRoi, index: 1)
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

    func upscaleRoiCb(cb: MTLCommandBuffer, scale: Float) {
        var s = scale
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(kSRNearest)
        enc.setTexture(texCbRoi, index: 0)
        enc.setTexture(texCbRoiSR, index: 1)
        enc.setBytes(&s, length: 4, index: 0)
        enc.dispatchThreadgroups(
            MTLSize(width: (srW + 15) / 16,
                    height: (srH + 15) / 16,
                    depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        enc.endEncoding()
    }

    func prepareCbChain(pixelBuffer: CVPixelBuffer,
                        roi: CGRect,
                        srScale: Float,
                        config: DotDetectorConfig)
    {
        extractCb(pixelBuffer: pixelBuffer)

        let rw = Int(roi.width)
        let rh = Int(roi.height)
        ensureRoiSize(rw, rh)

        let sw = max(1, Int(Float(rw) * srScale))
        let sh = max(1, Int(Float(rh) * srScale))
        ensureRoiSRSize(sw, sh)

        let cb1 = queue.makeCommandBuffer()!
        cropRoiCb(cb: cb1, roi: roi)
        cb1.commit()

        let cb2 = queue.makeCommandBuffer()!
        let (minTex, maxTex) = computeRoiMinMax(cb: cb2)
        cb2.commit()

        let cb3 = queue.makeCommandBuffer()!
        normalizeRoi(cb: cb3, minTex: minTex, maxTex: maxTex)
        cb3.commit()

        let cb4 = queue.makeCommandBuffer()!
        edgeRoi(cb: cb4)
        cb4.commit()

        let cb5 = queue.makeCommandBuffer()!
        upscaleRoiCb(cb: cb5, scale: srScale)
        cb5.commit()
    }

    func debugCbEdgeTexture() -> MTLTexture? {
        return texCbEdge
    }

    func debugCbRoiTexture() -> MTLTexture? {
        return texCbRoi
    }

    func debugCbRoiSRTexture() -> MTLTexture? {
        return texCbRoiSR
    }
}
