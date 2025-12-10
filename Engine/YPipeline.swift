// YPipeline.swift

import Foundation
import Metal
import CoreVideo
import simd

final class YPipeline {

    let device: MTLDevice
    let queue: MTLCommandQueue
    let cache: CVMetalTextureCache

    let kExtract: MTLComputePipelineState
    let kMin: MTLComputePipelineState
    let kMax: MTLComputePipelineState
    let kNorm: MTLComputePipelineState
    let kEdge: MTLComputePipelineState
    let kRoi: MTLComputePipelineState
    let kSR: MTLComputePipelineState

    var texY: MTLTexture?
    var texYNorm: MTLTexture?
    var texYEdge: MTLTexture?

    var texYRoi: MTLTexture?
    var texYRoiSR: MTLTexture?

    var width: Int = 0
    var height: Int = 0
    var roiWidth: Int = 0
    var roiHeight: Int = 0
    var srWidth: Int = 0
    var srHeight: Int = 0

    init(device: MTLDevice, queue: MTLCommandQueue, cache: CVMetalTextureCache, library: MTLLibrary) {
        self.device = device
        self.queue = queue
        self.cache = cache
        self.kExtract = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_extract")!)
        self.kMin = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_min")!)
        self.kMax = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_max")!)
        self.kNorm = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_norm")!)
        self.kEdge = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_y_edge")!)
        self.kRoi = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_roi_crop")!)
        self.kSR = try! device.makeComputePipelineState(function: library.makeFunction(name: "k_sr_nearest")!)
    }
}
// YPipeline.swift  (Segment 2)

extension YPipeline {

    func ensureFrameSize(_ w: Int, _ h: Int) {
        if w == width && h == height { return }
        width = w
        height = h
        texY = nil
        texYNorm = nil
        texYEdge = nil
    }

    func makeR8(_ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)!
    }

    func extractY(_ pb: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        ensureFrameSize(w, h)

        var texRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .r8Unorm, w, h, 0, &texRef)
        if let t = texRef { texY = CVMetalTextureGetTexture(t) }
    }

    func allocateFrameTextures() {
        if texYNorm == nil { texYNorm = makeR8(width, height) }
        if texYEdge == nil { texYEdge = makeR8(width, height) }
    }

    func prepareFrame(_ pb: CVPixelBuffer) {
        extractY(pb)
        allocateFrameTextures()
    }
}
// YPipeline.swift  (Segment 3)

extension YPipeline {

    func ensureRoiSize(_ w: Int, _ h: Int, _ sw: Int, _ sh: Int) {
        if roiW == w && roiH == h && roiSrw == sw && roiSrh == sh { return }
        roiW = w
        roiH = h
        roiSrw = sw
        roiSrh = sh
        texYRoi = makeR8(w, h)
        texYRoiSR = makeR8(sw, sh)
    }

    func cropRoi(_ cb: MTLCommandBuffer, src: MTLTexture, roi: CGRect) {
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpRoi)
        var xywh = SIMD4<UInt32>(
            UInt32(roi.origin.x),
            UInt32(roi.origin.y),
            UInt32(roi.size.width),
            UInt32(roi.size.height)
        )
        enc.setBuffer(device.makeBuffer(bytes: &xywh, length: MemoryLayout<SIMD4<UInt32>>.size), offset: 0, index: 0)
        enc.setTexture(src, index: 0)
        enc.setTexture(texYRoi, index: 1)
        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (roiW + tgW - 1) / tgW,
                         height: (roiH + tgH - 1) / tgH,
                         depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    func srNearest(_ cb: MTLCommandBuffer, scale: Float) {
        var sc = scale
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpSR)
        enc.setBuffer(device.makeBuffer(bytes: &sc, length: MemoryLayout<Float>.size), offset: 0, index: 0)
        enc.setTexture(texYRoi, index: 0)
        enc.setTexture(texYRoiSR, index: 1)
        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (roiSrw + tgW - 1) / tgW,
                         height: (roiSrh + tgH - 1) / tgH,
                         depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    func computeYEdge(_ cb: MTLCommandBuffer) {
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpYEdge)
        enc.setTexture(texYNorm, index: 0)
        enc.setTexture(texYEdge, index: 1)
        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (width + tgW - 1) / tgW,
                         height: (height + tgH - 1) / tgH,
                         depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    func prepareRoiPipeline(_ roi: CGRect, srScale: Float) {
        let rw = Int(roi.size.width)
        let rh = Int(roi.size.height)
        let sw = max(1, Int(Float(rw) * srScale))
        let sh = max(1, Int(Float(rh) * srScale))
        ensureRoiSize(rw, rh, sw, sh)

        let cb1 = nextCB()
        cropRoi(cb1, src: texYNorm, roi: roi)
        cb1.commit()

        let cb2 = nextCB()
        srNearest(cb2, scale: srScale)
        cb2.commit()
    }

    func prepareEdgePipeline() {
        let cb = nextCB()
        computeYEdge(cb)
        cb.commit()
    }
}
// YPipeline.swift  (Segment 4)

extension YPipeline {

    func ensureFast9Textures(_ w: Int, _ h: Int) {
        if fast9W == w && fast9H == h { return }
        fast9W = w
        fast9H = h
        texFast9 = makeR8(w, h)
        texFast9Score = makeR8(w, h)
    }

    func computeFast9(_ cb: MTLCommandBuffer, threshold: Float) {
        var thr = threshold
        let buf = device.makeBuffer(bytes: &thr, length: MemoryLayout<Float>.size)

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpFast9)
        enc.setTexture(texYRoiSR, index: 0)
        enc.setTexture(texFast9, index: 1)
        enc.setTexture(texFast9Score, index: 2)
        enc.setBuffer(buf, offset: 0, index: 0)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(
            width: (roiSrw + tgW - 1) / tgW,
            height: (roiSrh + tgH - 1) / tgH,
            depth: 1
        )
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    func prepareFast9Pipeline(_ threshold: Float) {
        ensureFast9Textures(roiSrw, roiSrh)
        let cb = nextCB()
        computeFast9(cb, threshold: threshold)
        cb.commit()
    }

    func readFast9(into ptr: UnsafeMutablePointer<UInt8>, outW: inout Int, outH: inout Int) {
        guard let tex = texFast9 else {
            outW = 0
            outH = 0
            return
        }
        outW = fast9W
        outH = fast9H
        let region = MTLRegionMake2D(0, 0, fast9W, fast9H)
        tex.getBytes(ptr, bytesPerRow: fast9W, from: region, mipmapLevel: 0)
    }

    func debugTexYNorm() -> MTLTexture? {
        return texYNorm
    }

    func debugTexYEdge() -> MTLTexture? {
        return texYEdge
    }

    func debugTexFast9() -> MTLTexture? {
        return texFast9
    }

    func debugTexFast9Score() -> MTLTexture? {
        return texFast9Score
    }
}
