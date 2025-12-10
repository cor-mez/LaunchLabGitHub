// MetalRenderer.Textures.swift

import Metal
import Foundation

extension MetalRendererCore {

    // MARK: - Texture Group

    struct TextureGroup {
        // Y full-frame
        var texY: MTLTexture?
        var texYNorm: MTLTexture?
        var texYEdge: MTLTexture?

        // Y ROI + SR
        var texYRoi: MTLTexture?
        var texYRoiSR: MTLTexture?

        // Y FAST9
        var texFast9Y: MTLTexture?
        var texFast9YScore: MTLTexture?

        // Cb full-frame
        var texCb: MTLTexture?
        var texCbNorm: MTLTexture?
        var texCbEdge: MTLTexture?

        // Cb ROI + SR
        var texCbRoi: MTLTexture?
        var texCbRoiSR: MTLTexture?

        // Cb FAST9
        var texFast9Cb: MTLTexture?
        var texFast9CbScore: MTLTexture?

        // Debug Surfaces
        var texDebugYNorm: MTLTexture?
        var texDebugYEdge: MTLTexture?
        var texDebugCbEdge: MTLTexture?
        var texDebugFast9Y: MTLTexture?
        var texDebugFast9Cb: MTLTexture?
    }

    // Shared persistent texture store
    private static var _sharedTextures = TextureGroup()

    var textures: TextureGroup {
        get { MetalRendererCore._sharedTextures }
        set { MetalRendererCore._sharedTextures = newValue }
    }

    // MARK: - Allocation Helpers

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

    // MARK: - Frame Size Y

    func ensureFrameYSize(width: Int, height: Int) {
        if frameW == width && frameH == height { return }
        frameW = width
        frameH = height

        textures.texY = makeR8(width, height)
        textures.texYNorm = makeR8(width, height)
        textures.texYEdge = makeR8(width, height)
    }

    // MARK: - Frame Size Cb

    func ensureFrameCbSize(width: Int, height: Int) {
        let cw = width / 2
        let ch = height / 2
        if cbFrameW == cw && cbFrameH == ch { return }

        cbFrameW = cw
        cbFrameH = ch

        textures.texCb = makeR8(cw, ch)
        textures.texCbNorm = makeR8(width, height)
        textures.texCbEdge = makeR8(width, height)
    }

    // MARK: - ROI Y Size

    func ensureRoiYSize(width: Int, height: Int) {
        if roiYW == width && roiYH == height { return }
        roiYW = width
        roiYH = height
        textures.texYRoi = makeR8(width, height)
    }

    // MARK: - ROI Cb Size

    func ensureRoiCbSize(width: Int, height: Int) {
        let cw = width / 2
        let ch = height / 2
        if roiCbW == cw && roiCbH == ch { return }
        roiCbW = cw
        roiCbH = ch
        textures.texCbRoi = makeR8(cw, ch)
    }

    // MARK: - SR Y Size

    func ensureSRYSize(width: Int, height: Int) {
        if srYW == width && srYH == height { return }
        srYW = width
        srYH = height

        textures.texYRoiSR = makeR8(width, height)
        textures.texFast9Y = makeR8(width, height)
        textures.texFast9YScore = makeR8(width, height)
    }

    // MARK: - SR Cb Size

    func ensureSRCbSize(width: Int, height: Int) {
        if srCbW == width && srCbH == height { return }
        srCbW = width
        srCbH = height

        textures.texCbRoiSR = makeR8(width, height)
        textures.texFast9Cb = makeR8(width, height)
        textures.texFast9CbScore = makeR8(width, height)
    }

    // MARK: - Debug Texture Allocation

    func allocDebugYNorm() {
        if let src = textures.texYNorm {
            textures.texDebugYNorm = makeR8(src.width, src.height)
        }
    }

    func allocDebugYEdge() {
        if let src = textures.texYEdge {
            textures.texDebugYEdge = makeR8(src.width, src.height)
        }
    }

    func allocDebugCbEdge() {
        if let src = textures.texCbEdge {
            textures.texDebugCbEdge = makeR8(src.width, src.height)
        }
    }

    func allocDebugFast9Y() {
        if let src = textures.texFast9Y {
            textures.texDebugFast9Y = makeR8(src.width, src.height)
        }
    }

    func allocDebugFast9Cb() {
        if let src = textures.texFast9Cb {
            textures.texDebugFast9Cb = makeR8(src.width, src.height)
        }
    }
}
