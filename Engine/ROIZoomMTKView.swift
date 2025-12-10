import MetalKit
import CoreVideo
import CoreGraphics
import simd

final class ROIZoomMTKView: MTKView {

    var renderer = MetalCameraRenderer.shared
    var weakPixelBuffer: WeakPixelBuffer?
    var roi: CGRect = .zero
    var zoomScale: CGFloat = 1.0

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
        guard let pb = weakPixelBuffer?.buffer else { return }
        renderer.drawRoiZoom(
            pixelBuffer: pb,
            in: self,
            roi: roi,
            zoomScale: Float(zoomScale)
        )
    }
}
