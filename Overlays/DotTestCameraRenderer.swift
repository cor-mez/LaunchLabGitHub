// DotTestCameraRenderer.swift v4A

import Foundation
import MetalKit
import CoreVideo

final class DotTestCameraRenderer {

    static let shared = DotTestCameraRenderer()

    private let renderer = MetalCameraRenderer.shared
    private let device = MetalCameraRenderer.shared.device
    private let queue = MetalCameraRenderer.shared.queue

    private init() {}

    func drawCPUTexture(_ tex: MTLTexture?, in view: MTKView) {
        renderer.drawTexture(tex, in: view)
    }

    func drawDebugSurface(_ surface: DotTestDebugSurface, in view: MTKView) {
        switch surface {
        case .none:
            clear(view)

        case .yNorm:
            renderer.drawDebugYNorm(in: view)

        case .yEdge:
            renderer.drawDebugYEdge(in: view)

        case .cbEdge:
            renderer.drawDebugCbEdge(in: view)

        case .fast9:
            renderer.drawDebugFast9Y(in: view)
        }
    }

    func drawSideBySide(cpuTexture: MTLTexture?,
                        gpuSurface: DotTestDebugSurface,
                        in view: MTKView)
    {
        guard let drawable = view.currentDrawable else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: desc) else { return }

        let w = drawable.texture.width
        let h = drawable.texture.height
        let half = Double(w) * 0.5

        var left = MTLViewport(originX: 0, originY: 0,
                               width: half, height: Double(h),
                               znear: 0, zfar: 1)

        var right = MTLViewport(originX: half, originY: 0,
                                width: half, height: Double(h),
                                znear: 0, zfar: 1)

        if let cpuTex = cpuTexture {
            enc.setViewport(left)
            renderer.encodeTexture(cpuTex, into: enc)
        }

        if let gpuTex = textureForSurface(gpuSurface) {
            enc.setViewport(right)
            renderer.encodeTexture(gpuTex, into: enc)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private func textureForSurface(_ surface: DotTestDebugSurface) -> MTLTexture? {
        switch surface {
        case .none:
            return nil
        case .yNorm:
            return renderer.debugYNormTexture()
        case .yEdge:
            return renderer.debugYEdgeTexture()
        case .cbEdge:
            return renderer.debugCbEdgeTexture()
        case .fast9:
            return renderer.debugFast9YTexture()
        }
    }

    func renderCamera(_ pb: CVPixelBuffer?, in view: MTKView) {
        renderer.drawPreviewY(pb, in: view)
    }

    private func clear(_ view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
