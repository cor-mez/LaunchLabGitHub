// CbPipeline.swift

import Metal
import CoreVideo
import simd

final class CbPipeline {

    let device: MTLDevice
    let queue: MTLCommandQueue
    let cache: CVMetalTextureCache

    let cpCbExtract: MTLComputePipelineState
    let cpCbMin: MTLComputePipelineState
    let cpCbMax: MTLComputePipelineState
    let cpCbNorm: MTLComputePipelineState
    let cpCbEdge: MTLComputePipelineState
    let cpRoi: MTLComputePipelineState
    let cpSR: MTLComputePipelineState
    let cpFast9: MTLComputePipelineState

    let tgW = 16
    let tgH = 16

    var texCb: MTLTexture?
    var texCbNorm: MTLTexture?
    var texCbEdge: MTLTexture?

    var texCbRoi: MTLTexture?
    var texCbRoiSR: MTLTexture?

    var texFast9Cb: MTLTexture?
    var texFast9CbScore: MTLTexture?

    var frameW = 0
    var frameH = 0

    var roiW = 0
    var roiH = 0
    var roiSrw = 0
    var roiSrh = 0

    private var cmdRing: [MTLCommandBuffer?] = [nil, nil, nil]
    private var cmdIndex = 0

    init(device: MTLDevice,
         queue: MTLCommandQueue,
         cache: CVMetalTextureCache,
         lib: MTLLibrary) {

        self.device = device
        self.queue = queue
        self.cache = cache

        cpCbExtract = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_cb_extract")!)
        cpCbMin = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_cb_min")!)
        cpCbMax = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_cb_max")!)
        cpCbNorm = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_cb_norm")!)
        cpCbEdge = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_chroma_edge")!)
        cpRoi = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_roi_crop")!)
        cpSR = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_sr_nearest")!)
        cpFast9 = try! device.makeComputePipelineState(function: lib.makeFunction(name: "k_fast9_gpu")!)
    }

    func nextCB() -> MTLCommandBuffer {
        cmdIndex = (cmdIndex &+ 1) % 3
        let cb = queue.makeCommandBuffer()!
        cmdRing[cmdIndex] = cb
        return cb
    }

    func makeR8(_ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }

    func ensureFrame(_ w: Int, _ h: Int) {
        if frameW == w && frameH == h { return }
        frameW = w
        frameH = h
        texCb = nil
        texCbNorm = nil
        texCbEdge = nil
    }

    func extractCb(_ pb: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        ensureFrame(w, h)

        let cw = w / 2
        let ch = h / 2

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .rg8Unorm, cw, ch, 1, &tmp)
        guard let chroma = tmp.flatMap({ CVMetalTextureGetTexture($0) }) else { return }

        texCb = makeR8(cw, ch)

        let cb = nextCB()
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpCbExtract)
        enc.setTexture(chroma, index: 0)
        enc.setTexture(texCb, index: 1)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (cw + tgW - 1) / tgW,
                         height: (ch + tgH - 1) / tgH,
                         depth: 1)

        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
    }

    func ensureCbNorm(_ w: Int, _ h: Int) {
        if texCbNorm?.width == w && texCbNorm?.height == h { return }
        texCbNorm = makeR8(w, h)
    }

    func computeCbNorm() {
        guard let cbTex = texCb else { return }

        ensureCbNorm(frameW, frameH)

        let minTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        minTexDesc.usage = [.shaderRead, .shaderWrite]
        let minTex = device.makeTexture(descriptor: minTexDesc)!

        let maxTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        maxTexDesc.usage = [.shaderRead, .shaderWrite]
        let maxTex = device.makeTexture(descriptor: maxTexDesc)!

        let cb = nextCB()
        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ngSmall = MTLSize(width: 1, height: 1, depth: 1)
        let ngFull = MTLSize(width: (cbTex.width + tgW - 1) / tgW,
                             height: (cbTex.height + tgH - 1) / tgH,
                             depth: 1)

        let e1 = cb.makeComputeCommandEncoder()!
        e1.setComputePipelineState(cpCbMin)
        e1.setTexture(cbTex, index: 0)
        e1.setTexture(minTex, index: 1)
        e1.dispatchThreadgroups(ngSmall, threadsPerThreadgroup: tg)
        e1.endEncoding()

        let e2 = cb.makeComputeCommandEncoder()!
        e2.setComputePipelineState(cpCbMax)
        e2.setTexture(cbTex, index: 0)
        e2.setTexture(maxTex, index: 1)
        e2.dispatchThreadgroups(ngSmall, threadsPerThreadgroup: tg)
        e2.endEncoding()

        let e3 = cb.makeComputeCommandEncoder()!
        e3.setComputePipelineState(cpCbNorm)
        e3.setTexture(cbTex, index: 0)
        e3.setTexture(texCbNorm, index: 1)
        e3.setTexture(minTex, index: 2)
        e3.setTexture(maxTex, index: 3)
        e3.dispatchThreadgroups(ngFull, threadsPerThreadgroup: tg)
        e3.endEncoding()

        cb.commit()
    }

    func computeCbEdge() {
        guard let norm = texCbNorm else { return }
        if texCbEdge?.width != frameW || texCbEdge?.height != frameH {
            texCbEdge = makeR8(frameW, frameH)
        }

        let cb = nextCB()
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpCbEdge)
        enc.setTexture(norm, index: 0)
        enc.setTexture(texCbEdge, index: 1)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (frameW + tgW - 1) / tgW,
                         height: (frameH + tgH - 1) / tgH,
                         depth: 1)

        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
    }

    func ensureRoi(_ w: Int, _ h: Int) {
        if roiW == w && roiH == h { return }
        roiW = w
        roiH = h
        texCbRoi = makeR8(w, h)
    }

    func cropCbRoi(_ roi: CGRect) {
        guard let norm = texCbNorm else { return }
        let x = Int(roi.origin.x)
        let y = Int(roi.origin.y)
        let w = Int(roi.width)
        let h = Int(roi.height)

        ensureRoi(w, h)

        let cb = nextCB()
        var roiData = SIMD4<Float>(Float(x), Float(y), Float(w), Float(h))
        let buf = device.makeBuffer(bytes: &roiData, length: MemoryLayout<SIMD4<Float>>.size)

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpRoi)
        enc.setTexture(norm, index: 0)
        enc.setTexture(texCbRoi, index: 1)
        enc.setBuffer(buf, offset: 0, index: 0)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (w + tgW - 1) / tgW,
                         height: (h + tgH - 1) / tgH,
                         depth: 1)

        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
    }

    func ensureRoiSR(_ w: Int, _ h: Int) {
        if roiSrw == w && roiSrh == h { return }
        roiSrw = w
        roiSrh = h
        texCbRoiSR = makeR8(w, h)
    }

    func upscaleCbRoi(_ scale: Float, roiW: Int, roiH: Int) {
        let sw = max(1, Int(Float(roiW) * scale))
        let sh = max(1, Int(Float(roiH) * scale))
        ensureRoiSR(sw, sh)

        let cb = nextCB()
        var s = scale
        let buf = device.makeBuffer(bytes: &s, length: MemoryLayout<Float>.size)

        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpSR)
        enc.setTexture(texCbRoi, index: 0)
        enc.setTexture(texCbRoiSR, index: 1)
        enc.setBuffer(buf, offset: 0, index: 0)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (sw + tgW - 1) / tgW,
                         height: (sh + tgH - 1) / tgH,
                         depth: 1)

        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
    }

    func ensureFast9(_ w: Int, _ h: Int) {
        if texFast9Cb?.width == w && texFast9Cb?.height == h { return }
        texFast9Cb = makeR8(w, h)
        texFast9CbScore = makeR8(w, h)
    }

    func computeFast9(_ threshold: Float) {
        guard let roiSR = texCbRoiSR else { return }

        let w = roiSR.width
        let h = roiSR.height
        ensureFast9(w, h)

        var thr = threshold
        let buf = device.makeBuffer(bytes: &thr, length: MemoryLayout<Float>.size)

        let cb = nextCB()
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(cpFast9)
        enc.setTexture(roiSR, index: 0)
        enc.setTexture(texFast9Cb, index: 1)
        enc.setTexture(texFast9CbScore, index: 2)
        enc.setBuffer(buf, offset: 0, index: 0)

        let tg = MTLSize(width: tgW, height: tgH, depth: 1)
        let ng = MTLSize(width: (w + tgW - 1) / tgW,
                         height: (h + tgH - 1) / tgH,
                         depth: 1)

        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
    }

    func readFast9(into ptr: UnsafeMutablePointer<UInt8>, outW: inout Int, outH: inout Int) {
        guard let tex = texFast9Cb else {
            outW = 0
            outH = 0
            return
        }
        outW = tex.width
        outH = tex.height
        let region = MTLRegionMake2D(0, 0, outW, outH)
        tex.getBytes(ptr, bytesPerRow: outW, from: region, mipmapLevel: 0)
    }

    func debugTexCbNorm() -> MTLTexture? { texCbNorm }
    func debugTexCbEdge() -> MTLTexture? { texCbEdge }
    func debugTexFast9Cb() -> MTLTexture? { texFast9Cb }
    func debugTexFast9CbScore() -> MTLTexture? { texFast9CbScore }
}
