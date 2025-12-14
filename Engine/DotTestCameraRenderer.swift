// DotTestCameraRenderer.swift
import Metal
import CoreVideo

@MainActor
final class DotTestCameraRenderer {

    static let shared = DotTestCameraRenderer()
    private init() {}

    func processFrame(
        _ pb: CVPixelBuffer,
        in view: DotTestPreviewView
    ) {
        let tex = makeCameraTexture(pb)

        view.render(
            texture: tex,
            isR8: true,
            forceSolidColor: false
        )
    }

    private func makeCameraTexture(_ pb: CVPixelBuffer) -> MTLTexture? {
        var cvTex: CVMetalTexture?

        let w = CVPixelBufferGetWidthOfPlane(pb, 0)
        let h = CVPixelBufferGetHeightOfPlane(pb, 0)

        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            MetalRenderer.shared.textureCache,
            pb,
            nil,
            .r8Unorm,
            w,
            h,
            0,
            &cvTex
        )

        return cvTex.flatMap { CVMetalTextureGetTexture($0) }
    }
}
