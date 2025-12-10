import Foundation
import Metal
import MetalKit

extension MetalRenderer {

    func drawTexture(_ tex: MTLTexture?, in view: MTKView) {
        guard let tex = tex else { return }
        guard let drawable = view.currentDrawable else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store

        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(p_preview)
        enc.setVertexBuffer(quad, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(samplerNearest, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    func blitTexture(_ tex: MTLTexture?, into target: MTLTexture?) {
        guard let tex = tex, let target = target else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store

        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: desc)!
        enc.setRenderPipelineState(p_blit)
        enc.setVertexBuffer(quad, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(samplerNearest, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.commit()
    }

    func drawDebugYNorm(in view: MTKView) {
        drawTexture(textures.texDebugYNorm, in: view)
    }

    func drawDebugYEdge(in view: MTKView) {
        drawTexture(textures.texDebugYEdge, in: view)
    }

    func drawDebugCbEdge(in view: MTKView) {
        drawTexture(textures.texDebugCbEdge, in: view)
    }

    func drawDebugFast9Y(in view: MTKView) {
        drawTexture(textures.texDebugFast9Y, in: view)
    }

    func drawDebugFast9Cb(in view: MTKView) {
        drawTexture(textures.texDebugFast9Cb, in: view)
    }

    func drawPreviewCamera(_ tex: MTLTexture?, in view: MTKView) {
        drawTexture(tex, in: view)
    }
}