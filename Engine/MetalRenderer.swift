// MetalRenderer.swift
// LaunchLab
//
// Single authoritative Metal preview renderer.
// No tiling, no reuse bugs, no debug fallbacks.
//

import Foundation
import Metal
import MetalKit
import CoreVideo

@MainActor
final class MetalRenderer {

    static let shared = MetalRenderer()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let previewPSO: MTLRenderPipelineState
    let sampler: MTLSamplerState
    let textureCache: CVMetalTextureCache

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("MTLCreateSystemDefaultDevice failed")
        }
        device = dev

        guard let q = dev.makeCommandQueue() else {
            fatalError("makeCommandQueue failed")
        }
        queue = q

        guard let lib = dev.makeDefaultLibrary() else {
            fatalError("makeDefaultLibrary failed")
        }
        library = lib

        let v = library.makeFunction(name: "passthroughVertex")!
        let f = library.makeFunction(name: "passthroughFragment")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            previewPSO = try dev.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create preview pipeline: \(error)")
        }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .nearest
        samplerDesc.magFilter = .nearest
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge

        guard let samp = dev.makeSamplerState(descriptor: samplerDesc) else {
            fatalError("Failed to create sampler")
        }
        sampler = samp

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        guard let c = cache else {
            fatalError("CVMetalTextureCacheCreate failed")
        }
        textureCache = c
    }

    // ---------------------------------------------------------
    // MARK: - CVPixelBuffer → Y-plane texture
    // ---------------------------------------------------------

    func makeYPlaneTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let plane = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)

        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            plane,
            &cvTex
        )

        guard
            status == kCVReturnSuccess,
            let metalTex = cvTex.flatMap({ CVMetalTextureGetTexture($0) })
        else {
            return nil
        }

        return metalTex
    }

    // ---------------------------------------------------------
    // MARK: - Preview Render (AUTHORITATIVE)
    // ---------------------------------------------------------

    func renderPreview(
        texture tex: MTLTexture,
        in view: MTKView
    ) {
        guard
            let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let cb = queue.makeCommandBuffer(),
            let enc = cb.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        // 🔑 CRITICAL: clear every frame (prevents tiling)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        enc.setRenderPipelineState(previewPSO)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)

        enc.setViewport(
            MTLViewport(
                originX: 0,
                originY: 0,
                width: Double(view.drawableSize.width),
                height: Double(view.drawableSize.height),
                znear: 0,
                zfar: 1
            )
        )

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()
    }
}
