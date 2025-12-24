// RenderPreview.swift

import Foundation
import Metal
import MetalKit

final class RenderPreview {

    static let shared = RenderPreview()
    private let previewEnabled = false
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipe: MTLRenderPipelineState
    let quad: MTLBuffer
    let sampler: MTLSamplerState

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!

        let lib = device.makeDefaultLibrary()!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "quad_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "preview_rgb_frag")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipe = try! device.makeRenderPipelineState(descriptor: desc)

        let quadData: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0
        ]
        quad = device.makeBuffer(bytes: quadData, length: quadData.count * MemoryLayout<Float>.size)!

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .nearest
        sd.magFilter = .nearest
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!
    }

    func draw(texture: MTLTexture?, in view: MTKView) {
        guard let tex = texture else { return }
        guard let drawable = view.currentDrawable else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store

        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(pipe)
        enc.setVertexBuffer(quad, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()
    }

    func drawY(_ tex: MTLTexture?, in view: MTKView) {
        draw(texture: tex, in: view)
    }

    func drawCb(_ tex: MTLTexture?, in view: MTKView) {
        draw(texture: tex, in: view)
    }

    func drawCbNorm(_ tex: MTLTexture?, in view: MTKView) {
        draw(texture: tex, in: view)
    }
}
