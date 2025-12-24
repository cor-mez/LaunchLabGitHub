import MetalKit
import UIKit

@MainActor
final class DotTestPreviewView: MTKView {

    private var currentTexture: MTLTexture?
    private var currentIsR8: Bool = false
    private var currentForceSolid: Bool = false

    private let overlayLayer = DotTestOverlayLayer()

    private var lastDrawTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 60.0

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

        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self

        overlayLayer.contentsScale = UIScreen.main.scale
        overlayLayer.isOpaque = false
        layer.addSublayer(overlayLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayLayer.frame = bounds
    }

    func render(
        texture: MTLTexture?,
        isR8: Bool,
        forceSolidColor: Bool
    ) {
        currentTexture = texture
        currentIsR8 = isR8
        currentForceSolid = forceSolidColor
        setNeedsDisplay()
    }

    func updateOverlay(
        fullSize: CGSize,
        roi: CGRect,
        sr: CGFloat
    ) {
        overlayLayer.update(
            fullSize: fullSize,
            roi: roi,
            sr: sr
        )
    }
}

extension DotTestPreviewView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {

        let now = CACurrentMediaTime()
        guard now - lastDrawTime >= minFrameInterval else { return }
        lastDrawTime = now

        guard let tex = currentTexture else { return }
        guard let _ = view.currentDrawable else { return }
        guard let _ = view.currentRenderPassDescriptor else { return }

        MetalRenderer.shared.renderPreview(
            texture: tex,
            in: view,
            isR8: currentIsR8,
            forceSolid: currentForceSolid
        )
    }
}
