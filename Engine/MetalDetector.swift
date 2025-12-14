//
//  MetalDetector.swift
//

import Foundation
import Metal
import CoreVideo
import simd

@MainActor
final class MetalDetector {
    
    static let shared = MetalDetector()
    
    // ======================================================================
    // MARK: - Metal Base Objects
    // ======================================================================
    
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    
    // ======================================================================
    // MARK: - Dynamic Tuning Params
    // ======================================================================
    
    var fast9ThresholdY: Int = 20
    var fast9ThresholdCb: Int = 20
    var fast9ScoreMinY: Int = 20
    var fast9ScoreMinCb: Int = 12
    var nmsRadius: Int = 1
    
    // ======================================================================
    // MARK: - Compute Pipelines (lazy = FIX for init ordering)
    // ======================================================================
    
    private lazy var p_extractY: MTLComputePipelineState = makePipeline("k_y_extract")
    private lazy var p_extractCb: MTLComputePipelineState = makePipeline("k_cb_extract")
    
    private lazy var p_edgeY:    MTLComputePipelineState = makePipeline("k_y_edge")
    private lazy var p_edgeCb:   MTLComputePipelineState = makePipeline("k_cb_edge")
    
    private lazy var p_fast9:    MTLComputePipelineState = makePipeline("k_fast9_gpu")
    private lazy var p_fast9Score: MTLComputePipelineState = makePipeline("k_fast9_score_gpu")
    
    // ======================================================================
    // MARK: - Working Texture Container
    // ======================================================================
    
    struct Working {
        var texY:       MTLTexture?
        var texCb:      MTLTexture?
        var texYEdge:   MTLTexture?
        var texCbEdge:  MTLTexture?
    }
    
    private(set) var work = Working()
    
    // ======================================================================
    // MARK: - Initializer
    // ======================================================================
    
    private init() {
        device  = MetalRenderer.shared.device
        queue   = MetalRenderer.shared.queue
        library = MetalRenderer.shared.library
    }
    
    // Utility factory
    private func makePipeline(_ name: String) -> MTLComputePipelineState {
        let fn = library.makeFunction(name: name)!
        return try! device.makeComputePipelineState(function: fn)
    }
    
    // ======================================================================
    // MARK: - PUBLIC ENTRY: PREPARE Y & Cb
    // ======================================================================
    
    func prepareFrameY(_ pb: CVPixelBuffer, roi: CGRect, srScale: Float) {
        ensureWorkingTextures(from: pb)
        
        guard let yTex = work.texY else { return }
        
        runExtractY(sourcePixelBuffer: pb, dst: yTex)
        
        // 🔽 NEW: ROI crop
        let roiTex = makeR8(Int(roi.width), Int(roi.height))
        
        var ox = UInt32(roi.origin.x)
        var oy = UInt32(roi.origin.y)
        
        runROICrop(
            src: yTex,
            dst: roiTex,
            ox: &ox,
            oy: &oy
        )
        
        work.texY = roiTex
        
        if let edge = work.texYEdge {
            runEdgeY(src: roiTex, dst: edge)
        }
    }
    
    func prepareFrameCb(_ pb: CVPixelBuffer, roi: CGRect, srScale: Float) {
        ensureWorkingTextures(from: pb)
        
        guard let cbTex = work.texCb else { return }
        guard let cbEdge = work.texCbEdge else { return }
        
        runExtractCb(sourcePixelBuffer: pb, dst: cbTex)
        runEdgeCb(src: cbTex, dst: cbEdge)
    }
    
    // ======================================================================
    // MARK: - GPU FAST9 ENTRY
    // ======================================================================
    struct ScoredPoint {
        let point: CGPoint
        let score: Float   // normalized 0–1
    }
    func gpuFast9ScoredCornersY() -> [ScoredPoint] {
        guard let edge = work.texYEdge else { return [] }

        let w = edge.width
        let h = edge.height

        let binTex   = makeFAST9Texture(width: w, height: h)
        let scoreTex = makeFAST9Texture(width: w, height: h)

        runFAST9(src: edge, dst: binTex, threshold: fast9ThresholdY)
        runFAST9Score(src: edge, dst: scoreTex, threshold: fast9ThresholdY)

        return readFAST9ScoredResults(binary: binTex, score: scoreTex)
    }
    func gpuFast9CornersYEnhanced() -> ([CGPoint], (mean: Float, min: Float, max: Float)) {
        
        guard let edge = work.texYEdge else { return ([], (0,0,0)) }
        
        let dst = makeFAST9Texture(width: edge.width, height: edge.height)
        runFAST9(src: edge, dst: dst, threshold: fast9ThresholdY)
        
        return readFAST9Results(dst)
    }
    
    func gpuFast9CornersCbEnhanced() -> ([CGPoint], (mean: Float, min: Float, max: Float)) {
        
        guard let cb = work.texCb else { return ([], (0,0,0)) }
        
        let dst = makeFAST9Texture(width: cb.width, height: cb.height)
        runFAST9(src: cb, dst: dst, threshold: fast9ThresholdCb)
        
        return readFAST9Results(dst)
    }
    
    // ======================================================================
    // MARK: - WORKING TEXTURE CREATION
    // ======================================================================

    private func ensureWorkingTextures(from pb: CVPixelBuffer) {

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        if work.texY == nil ||
           work.texY!.width  != w ||
           work.texY!.height != h {

            work.texY      = makeR8(w, h)
            work.texYEdge  = makeR8(w, h)
            work.texCb     = makeR8(w, h)
            work.texCbEdge = makeR8(w, h)
        }
        
        func makeR8(_ w: Int, _ h: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: w,
                height: h,
                mipmapped: false
            )
            d.usage = [.shaderRead, .shaderWrite]
            return device.makeTexture(descriptor: d)!
        }
        
        if work.texY == nil || work.texY?.width != w || work.texY?.height != h {
            work.texY      = makeR8(w, h)
            work.texYEdge  = makeR8(w, h)
            work.texCb     = makeR8(w, h)
            work.texCbEdge = makeR8(w, h)
        }
    }
    
    private func makeFAST9Texture(width: Int, height: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)!
    }
    
    // ======================================================================
    // MARK: - KERNEL RUNNERS
    // ======================================================================
    private func runFAST9Score(
        src: MTLTexture,
        dst: MTLTexture,
        threshold: Int
    ) {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }

        enc.setComputePipelineState(p_fast9Score)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)

        var thr = threshold
        enc.setBytes(&thr, length: MemoryLayout<Int>.size, index: 0)

        let w = p_fast9Score.threadExecutionWidth
        let h = max(1, p_fast9Score.maxTotalThreadsPerThreadgroup / w)

        enc.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )

        enc.endEncoding()
        cb.commit()
    }
    
    private func runExtractY(sourcePixelBuffer pb: CVPixelBuffer, dst: MTLTexture) {
        guard let src = makeTextureFromPixelBuffer(pb, plane: 0) else { return }
        runKernel(p_extractY, src: src, dst: dst)
    }
    
    private func runExtractCb(sourcePixelBuffer pb: CVPixelBuffer, dst: MTLTexture) {
        guard let src = makeTextureFromPixelBuffer(pb, plane: 1) else { return }
        runKernel(p_extractCb, src: src, dst: dst)
    }
    
    private func runEdgeY(src: MTLTexture, dst: MTLTexture) {
        runKernel(p_edgeY, src: src, dst: dst)
    }
    
    private func runEdgeCb(src: MTLTexture, dst: MTLTexture) {
        runKernel(p_edgeCb, src: src, dst: dst)
    }
    
    private func runFAST9(src: MTLTexture, dst: MTLTexture, threshold: Int) {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }
        
        enc.setComputePipelineState(p_fast9)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        
        var thr = threshold
        enc.setBytes(&thr, length: MemoryLayout<Int>.size, index: 0)
        
        let w = p_fast9.threadExecutionWidth
        let h = p_fast9.maxTotalThreadsPerThreadgroup / w
        
        enc.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        
        enc.endEncoding()
        cb.commit()
    }
    
    private func runKernel(_ pipeline: MTLComputePipelineState,
                           src: MTLTexture,
                           dst: MTLTexture)
    {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }
        
        enc.setComputePipelineState(pipeline)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        
        enc.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        
        enc.endEncoding()
        cb.commit()
    }
    
    // ======================================================================
    // MARK: - CVPixelBuffer → MTLTexture
    // ======================================================================
    
    private func makeTextureFromPixelBuffer(_ pb: CVPixelBuffer, plane: Int) -> MTLTexture? {
        
        var tmp: CVMetalTexture?
        let w = CVPixelBufferGetWidthOfPlane(pb, plane)
        let h = CVPixelBufferGetHeightOfPlane(pb, plane)
        
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            MetalRenderer.shared.textureCache,
            pb,
            nil,
            .r8Unorm,
            w,
            h,
            plane,
            &tmp
        )
        
        return tmp.flatMap { CVMetalTextureGetTexture($0) }
    }
    
    // ======================================================================
    // MARK: - FAST9 Readback
    // ======================================================================
    private func readFAST9ScoredResults(
        binary: MTLTexture,
        score: MTLTexture
    ) -> [ScoredPoint] {

        let w = binary.width
        let h = binary.height

        var bin = [Float](repeating: 0, count: w * h)
        var sc  = [Float](repeating: 0, count: w * h)

        binary.getBytes(
            &bin,
            bytesPerRow: w * MemoryLayout<Float>.size,
            from: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0
        )

        score.getBytes(
            &sc,
            bytesPerRow: w * MemoryLayout<Float>.size,
            from: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0
        )

        var out: [ScoredPoint] = []
        out.reserveCapacity(512)

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if bin[i] > 0 {
                    out.append(
                        ScoredPoint(
                            point: CGPoint(x: x, y: y),
                            score: sc[i]   // already normalized 0–1
                        )
                    )
                }
            }
        }

        return out
    }
    private func readFAST9Results(_ tex: MTLTexture)
    -> ([CGPoint], (Float, Float, Float))
    {
        let w = tex.width
        let h = tex.height
        
        var raw = [Float](repeating: 0, count: w * h)
        
        tex.getBytes(&raw,
                     bytesPerRow: w * MemoryLayout<Float>.size,
                     from: MTLRegionMake2D(0, 0, w, h),
                     mipmapLevel: 0)
        
        var pts: [CGPoint] = []
        var sum: Float = 0
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = 0
        var count: Int = 0
        
        for y in 0..<h {
            for x in 0..<w {
                let v = raw[y * w + x]
                if v > 0 {
                    pts.append(CGPoint(x: x, y: y))
                    sum += v
                    minV = min(minV, v)
                    maxV = max(maxV, v)
                    count += 1
                }
            }
        }
        
        return (pts, (count > 0 ? sum / Float(count) : 0, minV, maxV))
    }
    
    
    private func runROICrop(
        src: MTLTexture,
        dst: MTLTexture,
        ox: inout UInt32,
        oy: inout UInt32
    ) {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }
        
        let p = makePipeline("k_roi_crop_y")
        
        enc.setComputePipelineState(p)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&ox, length: 4, index: 0)
        enc.setBytes(&oy, length: 4, index: 1)
        
        enc.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        
        enc.endEncoding()
        cb.commit()
    }
    // ======================================================================
    // MARK: - Texture Helpers
    // ======================================================================
    
    private func makeR8(_ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)!
    }
    func filterByScore(
        points: [CGPoint],
        scores: [Float],
        minScore: Float
    ) -> [CGPoint] {
        guard points.count == scores.count else { return points }
        return zip(points, scores)
            .filter { $0.1 >= minScore }
            .map { $0.0 }
    }
}
