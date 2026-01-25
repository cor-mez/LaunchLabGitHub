//
//  MetalDetector.swift
//  LaunchLab
//
//  PHASE 2 — FAST9 GPU Observability
//
//  ROLE (STRICT):
//  - Execute FAST9 kernels on GPU
//  - Emit scored corner points ONLY
//  - No UI
//  - No authority
//  - No synthetic data
//

import Foundation
import Metal
import CoreGraphics
import QuartzCore

final class MetalDetector {

    static let shared = MetalDetector()

    // ---------------------------------------------------------------------
    // MARK: - Metal Core
    // ---------------------------------------------------------------------

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private let fast9Pipeline: MTLComputePipelineState
    private let fast9ScorePipeline: MTLComputePipelineState

    // ---------------------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------------------

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else {
            fatalError("Metal unavailable")
        }

        self.device = device
        self.commandQueue = queue

        do {
            let fast9 = library.makeFunction(name: "k_fast9_gpu")!
            let score = library.makeFunction(name: "k_fast9_score_gpu")!

            self.fast9Pipeline = try device.makeComputePipelineState(function: fast9)
            self.fast9ScorePipeline = try device.makeComputePipelineState(function: score)
        } catch {
            fatalError("Failed to build FAST9 pipelines: \(error)")
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Public API
    // ---------------------------------------------------------------------

    /// Executes FAST9 + score kernels and returns scored points.
    /// Safe for Phase-2 observability.
    func detectFAST9(
        srcTexture: MTLTexture,
        threshold: Int,
        completion: @escaping ([CGPoint]) -> Void
    ) {
        guard let cmd = commandQueue.makeCommandBuffer() else {
            completion([])
            return
        }

        let width = srcTexture.width
        let height = srcTexture.height
        let stride = width

        let pixelCount = width * height

        // -------------------------------------------------------------
        // Output buffers (CPU-readable)
        // -------------------------------------------------------------

        guard
            let binaryBuffer = device.makeBuffer(
                length: pixelCount,
                options: .storageModeShared
            ),
            let scoreBuffer = device.makeBuffer(
                length: pixelCount * MemoryLayout<Float>.size,
                options: .storageModeShared
            )
        else {
            completion([])
            return
        }

        // -------------------------------------------------------------
        // Encode FAST9 binary kernel
        // -------------------------------------------------------------

        encodeFAST9Binary(
            cmd: cmd,
            src: srcTexture,
            binaryOut: binaryBuffer,
            stride: stride,
            threshold: threshold,
            width: width,
            height: height
        )

        // -------------------------------------------------------------
        // Encode FAST9 score kernel
        // -------------------------------------------------------------

        encodeFAST9Score(
            cmd: cmd,
            src: srcTexture,
            scoreOut: scoreBuffer,
            stride: stride,
            threshold: threshold,
            width: width,
            height: height
        )

        // -------------------------------------------------------------
        // Completion handler — SAFE CPU readback
        // -------------------------------------------------------------

        cmd.addCompletedHandler { _ in
            let binary = binaryBuffer.contents().bindMemory(
                to: UInt8.self,
                capacity: pixelCount
            )
            let scores = scoreBuffer.contents().bindMemory(
                to: Float.self,
                capacity: pixelCount
            )

            var points: [CGPoint] = []
            points.reserveCapacity(512)

            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * stride + x
                    if binary[idx] != 0 {
                        let s = scores[idx]
                        if s > 0 {
                            points.append(CGPoint(x: x, y: y))
                        }
                    }
                }
            }

            completion(points)
        }

        cmd.commit()
    }

    // ---------------------------------------------------------------------
    // MARK: - Kernel Encoding (CORRECT ARGUMENT BINDING)
    // ---------------------------------------------------------------------

    private func encodeFAST9Binary(
        cmd: MTLCommandBuffer,
        src: MTLTexture,
        binaryOut: MTLBuffer,
        stride: Int,
        threshold: Int,
        width: Int,
        height: Int
    ) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }

        enc.setComputePipelineState(fast9Pipeline)

        // ⬇️ MUST MATCH Kernels_FAST9.metal EXACTLY
        enc.setTexture(src, index: 0)                // texture(0)
        enc.setBuffer(binaryOut, offset: 0, index: 0) // buffer(0)
        var strideU = UInt32(stride)
        enc.setBytes(&strideU, length: 4, index: 1)   // buffer(1)
        var thresh = threshold
        enc.setBytes(&thresh, length: 4, index: 2)    // buffer(2)

        dispatch(enc, pipeline: fast9Pipeline, width: width, height: height)
        enc.endEncoding()
    }

    private func encodeFAST9Score(
        cmd: MTLCommandBuffer,
        src: MTLTexture,
        scoreOut: MTLBuffer,
        stride: Int,
        threshold: Int,
        width: Int,
        height: Int
    ) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }

        enc.setComputePipelineState(fast9ScorePipeline)

        enc.setTexture(src, index: 0)
        enc.setBuffer(scoreOut, offset: 0, index: 0)
        var strideU = UInt32(stride)
        enc.setBytes(&strideU, length: 4, index: 1)
        var thresh = threshold
        enc.setBytes(&thresh, length: 4, index: 2)

        dispatch(enc, pipeline: fast9ScorePipeline, width: width, height: height)
        enc.endEncoding()
    }

    // ---------------------------------------------------------------------
    // MARK: - Dispatch Helper
    // ---------------------------------------------------------------------

    private func dispatch(
        _ enc: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)

        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)

        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
    }
}
