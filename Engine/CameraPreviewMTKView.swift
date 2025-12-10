import MetalKit
import CoreVideo

final class CameraPreviewMTKView: MTKView {

    var renderer = MetalCameraRenderer.shared
    var weakPixelBuffer: WeakPixelBuffer?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: MetalCameraRenderer.shared.device)
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        colorPixelFormat = .bgra8Unorm
        contentScaleFactor = UIScreen.main.scale
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MetalCameraRenderer.shared.device
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        colorPixelFormat = .bgra8Unorm
        contentScaleFactor = UIScreen.main.scale
    }

    override func draw(_ rect: CGRect) {
        renderer.draw(
            pixelBuffer: weakPixelBuffer?.buffer,
            in: self,
            mode: .previewY,
            roi: nil,
            zoomScale: 1.0
        )
    }
}
