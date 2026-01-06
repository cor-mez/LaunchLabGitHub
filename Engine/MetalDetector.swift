//
//  MetalDetector.swift
//  LaunchLab
//

import Foundation
import Metal
import CoreVideo
import CoreGraphics
import simd

final class MetalDetector {

    static let shared = MetalDetector()

    // ======================================================================
    // MARK: - Public Types
    // ======================================================================

    struct ScoredPoint {
        let point: CGPoint
        let score: Float   // normalized 0–1
    }

    // ======================================================================
    // MARK: - Metal Base Objects
    // ======================================================================

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    // Dedicated serial queue for all Metal work
    private let metalQueue = DispatchQueue(
        label: "launchlab.metal.detector",
        qos: .userInitiated
    )

    // ======================================================================
    // MARK: - Dynamic Tuning Params
    // ======================================================================

    var fast9ThresholdY: Int = 20

    // ======================================================================
    // MARK: - Compute Pipelines
    // ======================================================================

    private lazy var p_extractY: MTLComputePipelineState = makePipeline("k_y_extract")
    private lazy var p_edgeY:    MTLComputePipelineState = makePipeline("k_y_edge")
    private lazy var p_fast9:    MTLComputePipelineState = makePipeline("k_fast9_gpu")
    private lazy var p_fast9Score: MTLComputePipelineState = makePipeline("k_fast9_score_gpu")

    // ======================================================================
    // MARK: - Working Texture Container
    // ======================================================================

    struct Working {
        var texY: MTLTexture?
        var texYEdge: MTLTexture?
    }

    private(set) var work = Working()

    // ======================================================================
    // MARK: - Init
    // ======================================================================

    private init() {
        device  = MetalRenderer.shared.device
        queue   = MetalRenderer.shared.queue
        library = MetalRenderer.shared.library
    }

    private func makePipeline(_ name: String) -> MTLComputePipelineState {
        let fn = library.makeFunction(name: name)!
        return try! device.makeComputePipelineState(function: fn)
    }

    // ======================================================================
    // MARK: - Frame Preparation (ASYNC)
    // ======================================================================

    func prepareFrameY(
        _ pb: CVPixelBuffer,
        roi: CGRect,
        srScale: Float,
        completion: @escaping () -> Void
    ) {
        metalQueue.async {

            self.ensureWorkingTextures(from: pb)
            guard let yTex = self.work.texY else {
                completion()
                return
            }

            self.runExtractY(sourcePixelBuffer: pb, dst: yTex)

            let roiTex = self.makeR8(Int(roi.width), Int(roi.height))
            var ox = UInt32(roi.origin.x)
            var oy = UInt32(roi.origin.y)

            self.runROICrop(src: yTex, dst: roiTex, ox: &ox, oy: &oy)
            self.work.texY = roiTex

            if let edge = self.work.texYEdge {
                self.runEdgeY(src: roiTex, dst: edge)
            }

            completion()
        }
    }

    // ======================================================================
    // MARK: - FAST9 (ASYNC)
    // ======================================================================

    func gpuFast9ScoredCornersY(
        completion: @escaping ([ScoredPoint]) -> Void
    ) {
        metalQueue.async {

            guard let edge = self.work.texYEdge else {
                completion([])
                return
            }

            let w = edge.width
            let h = edge.height

            let binTex   = self.makeFAST9Texture(width: w, height: h)
            let scoreTex = self.makeFAST9Texture(width: w, height: h)

            self.runFAST9(src: edge, dst: binTex, threshold: self.fast9ThresholdY)
            self.runFAST9Score(src: edge, dst: scoreTex, threshold: self.fast9ThresholdY)

            let results = self.readFAST9ScoredResults(
                binary: binTex,
                score: scoreTex
            )

            completion(results)
        }
    }

    // ======================================================================
    // MARK: - Working Textures
    // ======================================================================

    private func ensureWorkingTextures(from pb: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        if work.texY == nil || work.texY!.width != w || work.texY!.height != h {
            work.texY = makeR8(w, h)
            work.texYEdge = makeR8(w, h)
        }
    }

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
    // MARK: - Kernels
    // ======================================================================

    private func runExtractY(sourcePixelBuffer pb: CVPixelBuffer, dst: MTLTexture) {
        guard let src = makeTextureFromPixelBuffer(pb, plane: 0) else { return }
        runKernel(p_extractY, src: src, dst: dst)
    }

    private func runEdgeY(src: MTLTexture, dst: MTLTexture) {
        runKernel(p_edgeY, src: src, dst: dst)
    }

    private func runFAST9(src: MTLTexture, dst: MTLTexture, threshold: Int) {
        runKernel(p_fast9, src: src, dst: dst, threshold: threshold)
    }

    private func runFAST9Score(src: MTLTexture, dst: MTLTexture, threshold: Int) {
        runKernel(p_fast9Score, src: src, dst: dst, threshold: threshold)
    }

    private func runKernel(
        _ pipeline: MTLComputePipelineState,
        src: MTLTexture,
        dst: MTLTexture,
        threshold: Int? = nil
    ) {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }

        enc.setComputePipelineState(pipeline)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)

        if var t = threshold {
            enc.setBytes(&t, length: MemoryLayout<Int>.size, index: 0)
        }

        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)

        enc.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )

        enc.endEncoding()
        cb.commit()
    }

    private func runROICrop(
        src: MTLTexture,
        dst: MTLTexture,
        ox: inout UInt32,
        oy: inout UInt32
    ) {
        let p = makePipeline("k_roi_crop_y")

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder()
        else { return }

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
    // MARK: - Readback
    // ======================================================================

    private func readFAST9ScoredResults(
        binary: MTLTexture,
        score: MTLTexture
    ) -> [ScoredPoint] {

        let w = binary.width
        let h = binary.height

        var bin = [Float](repeating: 0, count: w * h)
        var sc  = [Float](repeating: 0, count: w * h)

        binary.getBytes(&bin,
                        bytesPerRow: w * MemoryLayout<Float>.size,
                        from: MTLRegionMake2D(0, 0, w, h),
                        mipmapLevel: 0)

        score.getBytes(&sc,
                       bytesPerRow: w * MemoryLayout<Float>.size,
                       from: MTLRegionMake2D(0, 0, w, h),
                       mipmapLevel: 0)

        var out: [ScoredPoint] = []

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if bin[i] > 0 {
                    out.append(
                        ScoredPoint(
                            point: CGPoint(x: x, y: y),
                            score: sc[i]
                        )
                    )
                }
            }
        }

        return out
    }

    // ======================================================================
    // MARK: - PixelBuffer → Texture
    // ======================================================================

    private func makeTextureFromPixelBuffer(
        _ pb: CVPixelBuffer,
        plane: Int
    ) -> MTLTexture? {

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
}
