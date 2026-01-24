import Foundation
import Metal
import CoreVideo
import CoreGraphics
import simd
import QuartzCore

final class MetalDetector {

    static let shared = MetalDetector()

    // MARK: - Public Types
    struct ScoredPoint {
        let point: CGPoint
        let score: Float   // normalized 0–1
    }

    // MARK: - Metal Base Objects
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private let metalQueue = DispatchQueue(label: "launchlab.metal.detector",
                                          qos: .userInitiated)

    // MARK: - Dynamic Tuning Params
    var fast9ThresholdY: Int = 10   // Phase-2 discovery threshold

    // MARK: - Compute Pipelines
    private lazy var p_extractY: MTLComputePipelineState = makePipeline("k_y_extract")
    private lazy var p_edgeY:    MTLComputePipelineState = makePipeline("k_y_edge")
    private lazy var p_fast9:    MTLComputePipelineState = makePipeline("k_fast9_gpu")
    private lazy var p_fast9Score: MTLComputePipelineState = makePipeline("k_fast9_score_gpu")
    private lazy var p_roiCrop: MTLComputePipelineState = makePipeline("k_roi_crop_y")

    // MARK: - Working Texture Container
    struct Working {
        var texYFull: MTLTexture?
    }
    private(set) var work = Working()

    // MARK: - Init
    private init() {
        device  = MetalRenderer.shared.device
        queue   = MetalRenderer.shared.queue
        library = MetalRenderer.shared.library
    }

    private func makePipeline(_ name: String) -> MTLComputePipelineState {
        let fn = library.makeFunction(name: name)!
        return try! device.makeComputePipelineState(function: fn)
    }

    // MARK: - Frame Preparation & FAST9 (ASYNC)
    func prepareFrameY(
        _ pb: CVPixelBuffer,
        roi: CGRect,
        srScale: Float,
        completion: @escaping ([ScoredPoint]) -> Void
    ) {
        metalQueue.async {

            let fullWidth  = CVPixelBufferGetWidth(pb)
            let fullHeight = CVPixelBufferGetHeight(pb)

            let roiInt = CGRect(
                x: max(0, min(fullWidth  - 1, Int(roi.origin.x))),
                y: max(0, min(fullHeight - 1, Int(roi.origin.y))),
                width:  max(1, min(fullWidth  - Int(roi.origin.x), Int(roi.width))),
                height: max(1, min(fullHeight - Int(roi.origin.y), Int(roi.height)))
            )

            guard roiInt.width > 0, roiInt.height > 0 else {
                completion([])
                return
            }

            self.ensureFullYTexture(from: pb)
            guard let texYFull = self.work.texYFull else {
                completion([])
                return
            }

            let roiWidth  = Int(roiInt.width)
            let roiHeight = Int(roiInt.height)

            guard
                let roiTexY         = self.makeR8Optional(roiWidth, roiHeight),
                let roiTexEdge      = self.makeR8Optional(roiWidth, roiHeight),
                let roiTexFast9Bin  = self.makeFAST9TextureOptional(width: roiWidth, height: roiHeight),
                let roiTexFast9Score = self.makeFAST9TextureOptional(width: roiWidth, height: roiHeight)
            else {
                completion([])
                return
            }

            guard let commandBuffer = self.queue.makeCommandBuffer() else {
                completion([])
                return
            }

            // Y extract
            guard let srcTexture = self.makeTextureFromPixelBuffer(pb, plane: 0) else {
                completion([])
                return
            }

            self.encodeKernel(
                commandBuffer: commandBuffer,
                pipeline: self.p_extractY,
                src: srcTexture,
                dst: texYFull
            )

            // ROI crop
            var ox = UInt32(roiInt.origin.x)
            var oy = UInt32(roiInt.origin.y)

            self.encodeROICrop(
                commandBuffer: commandBuffer,
                src: texYFull,
                dst: roiTexY,
                ox: &ox,
                oy: &oy
            )

            // Edge + FAST9
            self.encodeKernel(
                commandBuffer: commandBuffer,
                pipeline: self.p_edgeY,
                src: roiTexY,
                dst: roiTexEdge
            )

            self.encodeKernel(
                commandBuffer: commandBuffer,
                pipeline: self.p_fast9,
                src: roiTexEdge,
                dst: roiTexFast9Bin,
                threshold: self.fast9ThresholdY
            )

            self.encodeKernel(
                commandBuffer: commandBuffer,
                pipeline: self.p_fast9Score,
                src: roiTexEdge,
                dst: roiTexFast9Score,
                threshold: self.fast9ThresholdY
            )

            let width  = roiWidth
            let height = roiHeight

            commandBuffer.addCompletedHandler { _ in
                let readStart = CACurrentMediaTime()

                var binData   = [Float](repeating: 0, count: width * height)
                var scoreData = [Float](repeating: 0, count: width * height)

                roiTexFast9Bin.getBytes(
                    &binData,
                    bytesPerRow: width * MemoryLayout<Float>.size,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )

                roiTexFast9Score.getBytes(
                    &scoreData,
                    bytesPerRow: width * MemoryLayout<Float>.size,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )

                var results: [ScoredPoint] = []

                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * width + x
                        if binData[i] > 0 {
                            results.append(
                                ScoredPoint(
                                    point: CGPoint(
                                        x: x + Int(ox),
                                        y: y + Int(oy)
                                    ),
                                    score: scoreData[i]
                                )
                            )
                        }
                    }
                }

                let latencyMs = Float((CACurrentMediaTime() - readStart) * 1000.0)

                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x40,                      // FAST9 readback
                    valueA: Float(results.count),
                    valueB: latencyMs
                )

                DispatchQueue.global().async {
                    completion(results)
                }
            }

            commandBuffer.commit()
        }
    }

    // MARK: - Working Textures
    private func ensureFullYTexture(from pb: CVPixelBuffer) {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        if work.texYFull == nil ||
            work.texYFull!.width != w ||
            work.texYFull!.height != h {
            work.texYFull = makeR8(w, h)
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
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    private func makeR8Optional(_ w: Int, _ h: Int) -> MTLTexture? {
        guard w > 0, h > 0 else { return nil }
        return makeR8(w, h)
    }

    private func makeFAST9Texture(width: Int, height: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    private func makeFAST9TextureOptional(width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        return makeFAST9Texture(width: width, height: height)
    }

    // MARK: - Kernel Encoding
    private func encodeKernel(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        src: MTLTexture,
        dst: MTLTexture,
        threshold: Int? = nil
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(dst, index: 1)
        if var t = threshold {
            encoder.setBytes(&t, length: MemoryLayout<Int>.size, index: 0)
        }
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
    }

    private func encodeROICrop(
        commandBuffer: MTLCommandBuffer,
        src: MTLTexture,
        dst: MTLTexture,
        ox: inout UInt32,
        oy: inout UInt32
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(p_roiCrop)
        encoder.setTexture(src, index: 0)
        encoder.setTexture(dst, index: 1)
        encoder.setBytes(&ox, length: 4, index: 0)
        encoder.setBytes(&oy, length: 4, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: dst.width, height: dst.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()
    }

    // MARK: - PixelBuffer → Texture
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
