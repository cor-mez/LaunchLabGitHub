//
//  MetalBilateral.swift
//  LaunchLab
//
//  Separable bilateral filter (horizontal + vertical) for Planar8 ROIs.
//  Outputs Planar8 buffer suitable for FAST9.
//

import Foundation
import Metal
import Accelerate

public final class MetalBilateralFilter {

    private let ctx = MetalContext.shared
    private let pipelineH: MTLComputePipelineState
    private let pipelineV: MTLComputePipelineState

    private let maxDim = 384    // ROI cap you selected

    public init() {
        do {
            pipelineH = try ctx.device.makeComputePipelineState(
                function: ctx.library.makeFunction(name: "bilateral_h")!
            )
            pipelineV = try ctx.device.makeComputePipelineState(
                function: ctx.library.makeFunction(name: "bilateral_v")!
            )
        } catch {
            fatalError("Metal bilateral pipeline creation failed: \(error)")
        }
    }

    // ---------------------------------------------------------
    // MARK: - API: Apply bilateral
    // ---------------------------------------------------------
    //
    // Input: Planar8 vImage_Buffer
    // Output: NEW Planar8 vImage_Buffer (caller must free)
    //

    public func apply(_ src: vImage_Buffer) -> vImage_Buffer? {
        let w = Int(src.width)
        let h = Int(src.height)

        guard w > 1, h > 1 else { return nil }
        guard w <= maxDim, h <= maxDim else { return nil }

        let device = ctx.device
        let queue  = ctx.queue

        // 1. Create MTLTextures from Planar8 input
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w, height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]

        guard let texIn = device.makeTexture(descriptor: desc),
              let texTmp = device.makeTexture(descriptor: desc),
              let texOut = device.makeTexture(descriptor: desc)
        else { return nil }

        // Upload src → texIn
        let bytesPerRow = src.rowBytes
        texIn.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: src.data,
            bytesPerRow: bytesPerRow
        )

        // 2. Horizontal pass
        guard let cmd1 = queue.makeCommandBuffer(),
              let enc1 = cmd1.makeComputeCommandEncoder()
        else { return nil }

        enc1.setComputePipelineState(pipelineH)
        enc1.setTexture(texIn, index: 0)
        enc1.setTexture(texTmp, index: 1)

        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let ng = MTLSize(
            width: (w + 15) / 16,
            height: (h + 15) / 16,
            depth: 1
        )
        enc1.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc1.endEncoding()
        cmd1.commit()
        cmd1.waitUntilCompleted()

        // 3. Vertical pass
        guard let cmd2 = queue.makeCommandBuffer(),
              let enc2 = cmd2.makeComputeCommandEncoder()
        else { return nil }

        enc2.setComputePipelineState(pipelineV)
        enc2.setTexture(texTmp, index: 0)
        enc2.setTexture(texOut, index: 1)
        enc2.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc2.endEncoding()
        cmd2.commit()
        cmd2.waitUntilCompleted()

        // 4. Create output vImage buffer
        let outBytes = w * h
        guard let outData = malloc(outBytes) else { return nil }

        var outBuf = vImage_Buffer(
            data: outData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )

        texOut.getBytes(
            outBuf.data,
            bytesPerRow: outBuf.rowBytes,
            from: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0
        )

        return outBuf
    }
}
