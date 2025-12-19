import MetalKit
import UIKit

@MainActor
final class FounderPreviewView: MTKView {
    private var currentTexture: MTLTexture?
    private var currentIsR8 = false
    private let overlayLayer = FounderOverlayLayer()

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MetalRenderer.shared.device)
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MetalRenderer.shared.device
        commonInit()
    }

    private func commonInit() {
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        isPaused = false
        enableSetNeedsDisplay = false
        delegate = self

        overlayLayer.contentsScale = UIScreen.main.scale
        overlayLayer.isOpaque = false
        layer.addSublayer(overlayLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayLayer.frame = bounds
    }

    func render(texture: MTLTexture?, isR8: Bool) {
        currentTexture = texture
        currentIsR8 = isR8
    }

    func updateOverlay(roi: CGRect, fullSize: CGSize, ballLocked: Bool, confidence: Float) {
        overlayLayer.update(roi: roi, fullSize: fullSize, ballLocked: ballLocked, confidence: confidence)
    }
}

extension FounderPreviewView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        MetalRenderer.shared.renderPreview(
            texture: currentTexture,
            in: self,
            isR8: currentIsR8,
            forceSolid: false
        )
    }
}
