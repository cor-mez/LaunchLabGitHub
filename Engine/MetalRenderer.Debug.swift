import Foundation
import Metal
import MetalKit

extension MetalRenderer {

    func debugTextureYNorm(in view: MTKView) {
        drawTexture(textures.texDebugYNorm, in: view)
    }

    func debugTextureYEdge(in view: MTKView) {
        drawTexture(textures.texDebugYEdge, in: view)
    }

    func debugTextureCbEdge(in view: MTKView) {
        drawTexture(textures.texDebugCbEdge, in: view)
    }

    func debugTextureFast9Y(in view: MTKView) {
        drawTexture(textures.texDebugFast9Y, in: view)
    }

    func debugTextureFast9Cb(in view: MTKView) {
        drawTexture(textures.texDebugFast9Cb, in: view)
    }

    func routeDebugSurface(_ surface: DotTestDebugSurface, in view: MTKView) {
        switch surface {
        case .yNorm:
            debugTextureYNorm(in: view)
        case .yEdge:
            debugTextureYEdge(in: view)
        case .cbEdge:
            debugTextureCbEdge(in: view)
        case .fast9y:
            debugTextureFast9Y(in: view)
        case .fast9cb:
            debugTextureFast9Cb(in: view)
        case .roi:
            if let tex = textures.texYRoi {
                drawTexture(tex, in: view)
            }
        }
    }
}