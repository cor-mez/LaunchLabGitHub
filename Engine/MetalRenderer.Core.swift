// MetalRenderer.Core.swift v4A

import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

final class MetalRendererCore {

    static let shared = MetalRendererCore()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let cache: CVMetalTextureCache

    let quad: MTLBuffer
    let samplerNearest: MTLSamplerState
    let samplerLinear: MTLSamplerState

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }

        device = dev
        queue = q
        library = device.makeDefaultLibrary()!

        var tc: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &tc)
        cache = tc!

        let quadData: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]

        quad = device.makeBuffer(
            bytes: quadData,
            length: quadData.count * MemoryLayout<Float>.size
        )!

        let sd0 = MTLSamplerDescriptor()
        sd0.minFilter = .nearest
        sd0.magFilter = .nearest
        sd0.sAddressMode = .clampToEdge
        sd0.tAddressMode = .clampToEdge
        samplerNearest = device.makeSamplerState(descriptor: sd0)!

        let sd1 = MTLSamplerDescriptor()
        sd1.minFilter = .linear
        sd1.magFilter = .linear
        sd1.sAddressMode = .clampToEdge
        sd1.tAddressMode = .clampToEdge
        samplerLinear = device.makeSamplerState(descriptor: sd1)!
    }

    // MARK: - Pipeline Builders

    func makeRenderPipeline(vertex: String, fragment: String) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertex)
        desc.fragmentFunction = library.makeFunction(name: fragment)
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try! device.makeRenderPipelineState(descriptor: desc)
    }

    func makeCompute(_ name: String) -> MTLComputePipelineState {
        let fn = library.makeFunction(name: name)!
        return try! device.makeComputePipelineState(function: fn)
    }

    // MARK: - Texture Builders

    func makeR8(_ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }

    func makeR32F(_ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: w,
            height: h,
            mipmapped: false
        )
        d.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }
}
