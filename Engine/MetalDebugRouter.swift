//
//  MetalDebugRouter.swift
//

import Foundation
import MetalKit

@MainActor
final class MetalDebugRouter {

    static let shared = MetalDebugRouter()

    private let renderer = MetalRenderer.shared
    private let mode     = DotTestMode.shared

    private init() {}

    // -------------------------------------------------------------------------
    // MARK: - Individual Texture Accessors
    // -------------------------------------------------------------------------

    func debugTextureYRaw()  -> MTLTexture? { renderer.textures.texY }
    func debugTextureYNorm() -> MTLTexture? { renderer.textures.texYNorm }
    func debugTextureYEdge() -> MTLTexture? { renderer.textures.texYEdge }

    func debugTextureCbRaw()  -> MTLTexture? { renderer.textures.texCb }
    func debugTextureCbNorm() -> MTLTexture? { renderer.textures.texCbNorm }
    func debugTextureCbEdge() -> MTLTexture? { renderer.textures.texCbEdge }

    func debugTextureFast9Y()  -> MTLTexture? { renderer.textures.texFast9Y }
    func debugTextureFast9Cb() -> MTLTexture? { renderer.textures.texFast9Cb }

    func debugTextureMismatchHeatmap() -> MTLTexture? {
        mode.mismatchHeatmapTexture
    }

    // -------------------------------------------------------------------------
    // MARK: - Unified Selector
    // -------------------------------------------------------------------------

    func texture(for surface: DotTestMode.DebugSurface) -> MTLTexture? {

        switch surface {

        case .yRaw:
            return debugTextureYRaw()

        case .yNorm:
            return debugTextureYNorm()

        case .yEdge:
            return debugTextureYEdge()

        case .cbRaw:
            return debugTextureCbRaw()

        case .cbNorm:
            return debugTextureCbNorm()

        case .cbEdge:
            return debugTextureCbEdge()

        case .fast9y:
            return debugTextureFast9Y()

        case .fast9cb:
            return debugTextureFast9Cb()

        case .mismatchHeatmap:
            return debugTextureMismatchHeatmap()

        case .mixedCorners:
            return nil
        }
    }
}
