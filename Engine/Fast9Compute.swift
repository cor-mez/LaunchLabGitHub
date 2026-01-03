//
//  Fast9Compute.swift
//

import Foundation
import Metal

final class Fast9Compute {

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    // GPU pipelines
    private let p_fast9:       MTLComputePipelineState
    private let p_fast9_score: MTLComputePipelineState

    init(device: MTLDevice,
         queue: MTLCommandQueue,
         library: MTLLibrary)
    {
        self.device  = device
        self.queue   = queue
        self.library = library

        p_fast9 = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_fast9_gpu")!
        )
        p_fast9_score = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "k_fast9_score_gpu")!
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - FAST9 Corner Mask (Binary)
    // -------------------------------------------------------------------------
    func detectCorners(from src: MTLTexture,
                       into dst: MTLTexture,
                       threshold: Int,
                       cb: MTLCommandBuffer)
    {
        var thr = Int32(threshold)

        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_fast9)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&thr, length: 4, index: 0)
        dispatch2D(enc, w: dst.width, h: dst.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - FAST9 Score Map
    // -------------------------------------------------------------------------
    func scoreCorners(from src: MTLTexture,
                      into dst: MTLTexture,
                      threshold: Int,
                      cb: MTLCommandBuffer)
    {
        var thr = Int32(threshold)

        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(p_fast9_score)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&thr, length: 4, index: 0)
        dispatch2D(enc, w: dst.width, h: dst.height)
        enc.endEncoding()
    }

    // -------------------------------------------------------------------------
    // MARK: - READBACK: Binary Mask (UInt8)
    // -------------------------------------------------------------------------
    func readBinaryFast9(from tex: MTLTexture,
                         into buffer: UnsafeMutablePointer<UInt8>)
    {
        let w = tex.width
        let h = tex.height

        tex.getBytes(buffer,
                     bytesPerRow: w * MemoryLayout<UInt8>.size,
                     from: MTLRegionMake2D(0, 0, w, h),
                     mipmapLevel: 0)
    }

    // -------------------------------------------------------------------------
    // MARK: - READBACK: Score Map (UInt8 → Float)
    // -------------------------------------------------------------------------
    func readScoreFast9(from tex: MTLTexture,
                        into buffer: UnsafeMutablePointer<Float>)
    {
        let w = tex.width
        let h = tex.height
        let count = w * h

        // Read into a temporary UInt8 array for conversion
        var tmp = [UInt8](repeating: 0, count: count)

        tex.getBytes(&tmp,
                     bytesPerRow: w * MemoryLayout<UInt8>.size,
                     from: MTLRegionMake2D(0, 0, w, h),
                     mipmapLevel: 0)

        // Convert byte → Float
        for i in 0..<count {
            buffer[i] = Float(tmp[i])
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Dispatch Helpers
    // -------------------------------------------------------------------------
    private func dispatch2D(_ enc: MTLComputeCommandEncoder,
                            w: Int,
                            h: Int)
    {
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let ng = MTLSize(width:  (w + 15) / 16,
                         height: (h + 15) / 16,
                         depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
    }
}
