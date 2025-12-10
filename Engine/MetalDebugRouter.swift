// MetalDebugRouter.swift v4A

import Foundation
import MetalKit
import CoreVideo

final class MetalDebugRouter {

    static let shared = MetalDebugRouter()

    private let renderer = MetalCameraRenderer.shared

    private init() {}

    func renderCamera(_ pb: CVPixelBuffer?, in view: MTKView) {
        renderer.drawPreviewY(pb, in: view)
    }

    func renderSurface(_ surface: DotTestDebugSurface, in view: MTKView) {
        switch surface {
        case .camera:
            renderCamera(nil, in: view)
        case .yNorm:
            renderer.drawDebugYNorm(in: view)
        case .yEdge:
            renderer.drawDebugYEdge(in: view)
        case .cbEdge:
            renderer.drawDebugCbEdge(in: view)
        case .fast9Y:
            renderer.drawDebugFast9Y(in: view)
        case .fast9Cb:
            renderer.drawDebugFast9Cb(in: view)
        }
    }

    func renderTexture(_ tex: MTLTexture?, in view: MTKView) {
        renderer.drawTexture(tex, in: view)
    }

    private func clear(_ view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let cb = renderer.queue.makeCommandBuffer()!
        let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
