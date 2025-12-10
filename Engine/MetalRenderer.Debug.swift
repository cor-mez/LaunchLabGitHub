import Foundation
import Metal
import MetalKit

// MARK: - DotTest Debug Surface Types

enum DotTestDebugSurface: String, CaseIterable {
    case none
    case yNorm
    case yEdge
    case cbEdge
    case fast9Y
    case fast9Cb
}

// MARK: - Debug Rendering Layer

extension MetalRendererCore {

    // MARK: - Public Entrypoint

    func drawDebugSurface(_ surface: DotTestDebugSurface, in view: MTKView) {
        switch surface {
        case .none:
            clearView(in: view)
        case .yNorm:
            drawTexture(textures.texDebugYNorm, in: view)
        case .yEdge:
            drawTexture(textures.texDebugYEdge, in: view)
        case .cbEdge:
            drawTexture(textures.texDebugCbEdge, in: view)
        case .fast9Y:
            drawTexture(textures.texDebugFast9Y, in: view)
        case .fast9Cb:
            drawTexture(textures.texDebugFast9Cb, in: view)
        }
    }

    // MARK: - Internal Helpers

    func prepareDebugCopies() {
        if let src = textures.texYNorm {
            if textures.texDebugYNorm == nil {
                textures.texDebugYNorm = makeR8(src.width, src.height)
            }
            blitCopy(src, to: textures.texDebugYNorm!)
        }

        if let src = textures.texYEdge {
            if textures.texDebugYEdge == nil {
                textures.texDebugYEdge = makeR8(src.width, src.height)
            }
            blitCopy(src, to: textures.texDebugYEdge!)
        }

        if let src = textures.texCbEdge {
            if textures.texDebugCbEdge == nil {
                textures.texDebugCbEdge = makeR8(src.width, src.height)
            }
            blitCopy(src, to: textures.texDebugCbEdge!)
        }

        if let src = textures.texFast9Y {
            if textures.texDebugFast9Y == nil {
                textures.texDebugFast9Y = makeR8(src.width, src.height)
            }
            blitCopy(src, to: textures.texDebugFast9Y!)
        }

        if let src = textures.texFast9Cb {
            if textures.texDebugFast9Cb == nil {
                textures.texDebugFast9Cb = makeR8(src.width, src.height)
            }
            blitCopy(src, to: textures.texDebugFast9Cb!)
        }
    }

    func blitCopy(_ src: MTLTexture, to dst: MTLTexture) {
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeBlitCommandEncoder()
        else { return }

        let region = MTLRegionMake2D(0, 0, src.width, src.height)

        enc.copy(
            from: src,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: region.origin,
            sourceSize: region.size,
            to: dst,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: region.origin
        )

        enc.endEncoding()
        cb.commit()
    }

    func clearView(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = drawable.texture
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].storeAction = .store

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rp)
        else { return }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}
