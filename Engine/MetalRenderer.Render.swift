import Foundation
import Metal
import MetalKit
import CoreVideo

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
        enc.setRenderPipelineState(renderPipeline)
        enc.setVertexBuffer(quad, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentSamplerState(samplerNearest, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    func drawCameraY(_ pb: CVPixelBuffer?, in view: MTKView) {
        guard let pb = pb else { return }
        YCompute.shared.prepareYChain(pixelBuffer: pb, roi: .zero, srScale: 1.0)
        drawTexture(YCompute.shared.texY, in: view)
    }

    func drawCameraCb(_ pb: CVPixelBuffer?, in view: MTKView) {
        guard let pb = pb else { return }
        CbCompute.shared.prepareCbChain(pixelBuffer: pb, roi: .zero, srScale: 1.0, config: DotDetectorConfig())
        drawTexture(CbCompute.shared.texCb, in: view)
    }

    func drawCameraCbNorm(_ pb: CVPixelBuffer?, in view: MTKView) {
        guard let pb = pb else { return }
        CbCompute.shared.prepareCbChain(pixelBuffer: pb, roi: .zero, srScale: 1.0, config: DotDetectorConfig())
        drawTexture(CbCompute.shared.texCbNorm, in: view)
    }
}

extension MetalRenderer {

    func drawDebugYNorm(in view: MTKView) {
        drawTexture(YCompute.shared.debugYNormTexture(), in: view)
    }

    func drawDebugYEdge(in view: MTKView) {
        drawTexture(YCompute.shared.debugYEdgeTexture(), in: view)
    }

    func drawDebugCbEdge(in view: MTKView) {
        drawTexture(CbCompute.shared.debugCbEdgeTexture(), in: view)
    }

    func drawDebugFast9Y(in view: MTKView) {
        drawTexture(Fast9Compute.shared.debugFast9YTexture(), in: view)
    }

    func drawDebugFast9Cb(in view: MTKView) {
        drawTexture(Fast9Compute.shared.debugFast9CbTexture(), in: view)
    }

    func drawDebugSurface(_ surface: DotTestDebugSurface, in view: MTKView) {
        switch surface {
        case .none:
            clear(in: view)
        case .yNorm:
            drawDebugYNorm(in: view)
        case .yEdge:
            drawDebugYEdge(in: view)
        case .cbEdge:
            drawDebugCbEdge(in: view)
        case .fast9Y:
            drawDebugFast9Y(in: view)
        case .fast9Cb:
            drawDebugFast9Cb(in: view)
        }
    }

    private func clear(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
