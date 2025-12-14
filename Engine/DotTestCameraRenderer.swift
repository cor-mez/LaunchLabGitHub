import Foundation
import Metal
import MetalKit
import CoreVideo

@MainActor
final class DotTestCameraRenderer {

    static let shared = DotTestCameraRenderer()

    private let renderer = MetalRenderer.shared
    private let coordinator = DotTestCoordinator.shared

    private init() {}

    func processFrame(_ pb: CVPixelBuffer, in view: DotTestPreviewView) {
        coordinator.processFrame(pb)

        DispatchQueue.main.async {
            self.renderPreview(pb, in: view)
            view.refreshCorners()
        }
    }

    private func renderPreview(_ pb: CVPixelBuffer, in view: MTKView) {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]

        guard let tex = renderer.device.makeTexture(descriptor: desc) else { return }

        var tmp: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil,
                                                  renderer.textureCache,
                                                  pb,
                                                  nil,
                                                  .r8Unorm,
                                                  w,
                                                  h,
                                                  0,
                                                  &tmp)

        if let ref = tmp, let src = CVMetalTextureGetTexture(ref) {
            let cb = renderer.queue.makeCommandBuffer()!
            let enc = cb.makeBlitCommandEncoder()!
            let region = MTLRegionMake2D(0, 0, w, h)
            enc.copy(from: src,
                     sourceSlice: 0,
                     sourceLevel: 0,
                     sourceOrigin: region.origin,
                     sourceSize: region.size,
                     to: tex,
                     destinationSlice: 0,
                     destinationLevel: 0,
                     destinationOrigin: region.origin)
            enc.endEncoding()
            cb.commit()

            renderer.drawPreviewCamera(tex, in: view)
        }

        view.setNeedsDisplay()
    }
}
