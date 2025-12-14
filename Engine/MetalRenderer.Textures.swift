//
// MetalRenderer.Textures.swift
// Clean modern texture container for DotTest debug surfaces
//

import Foundation
import Metal

// -----------------------------------------------------------------------------
// MARK: - TextureBundle
// Holds references to each intermediate / debug texture.
// The renderer does NOT compute sizes — MetalDetector provides real textures.
// -----------------------------------------------------------------------------

struct TextureBundle {

    // Y-plane pipeline textures
    var texY:       MTLTexture?
    var texYNorm:   MTLTexture?
    var texYEdge:   MTLTexture?

    // Cb-plane pipeline textures
    var texCb:      MTLTexture?
    var texCbNorm:  MTLTexture?
    var texCbEdge:  MTLTexture?

    // FAST9 surfaces
    var texFast9Y:  MTLTexture?
    var texFast9Cb: MTLTexture?

    // Mismatch heatmap
    var texHeatmap: MTLTexture?

    mutating func clearAll() {
        texY       = nil
        texYNorm   = nil
        texYEdge   = nil

        texCb      = nil
        texCbNorm  = nil
        texCbEdge  = nil

        texFast9Y  = nil
        texFast9Cb = nil

        texHeatmap = nil
    }
}

// -----------------------------------------------------------------------------
// MARK: - MetalRenderer extension
// -----------------------------------------------------------------------------

extension MetalRenderer {

    /// Shared texture bundle used by debug router and preview systems.
    var textures: TextureBundle {
        get { textureBundle }
        set { textureBundle = newValue }
    }

    // Private stored bundle
    private static var textureBundleStorage = TextureBundle()

    private var textureBundle: TextureBundle {
        get { Self.textureBundleStorage }
        set { Self.textureBundleStorage = newValue }
    }

    /// Helper: allocate a texture matching an existing texture's size and format.
    func makeLike(_ tex: MTLTexture?,
                  pixelFormat: MTLPixelFormat? = nil,
                  usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {

        guard let tex = tex else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat ?? tex.pixelFormat,
            width: tex.width,
            height: tex.height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = .shared

        return device.makeTexture(descriptor: desc)
    }

    /// Helper: allocate a texture with explicit size.
    func makeTexture(width: Int,
                     height: Int,
                     pixelFormat: MTLPixelFormat,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {

        guard width > 0, height > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = .shared

        return device.makeTexture(descriptor: desc)
    }
}
