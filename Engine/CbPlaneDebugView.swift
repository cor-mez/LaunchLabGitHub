import SwiftUI
import MetalKit
import CoreVideo

struct CbPlaneDebugView: UIViewRepresentable {

    @EnvironmentObject var camera: CameraManager
    var normalized: Bool = false

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MetalCameraRenderer.shared.device)
        v.framebufferOnly = false
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        v.colorPixelFormat = .bgra8Unorm
        v.contentScaleFactor = UIScreen.main.scale
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let pb = camera.latestWeakPixelBuffer.buffer else { return }
        uiView.drawableSize = CGSize(width: uiView.bounds.width * uiView.contentScaleFactor,
                                     height: uiView.bounds.height * uiView.contentScaleFactor)
        MetalCameraRenderer.shared.draw(
            pixelBuffer: pb,
            in: uiView,
            mode: normalized ? .previewCbNormalized : .previewCbRaw,
            roi: nil,
            zoomScale: 1.0
        )
    }
}
