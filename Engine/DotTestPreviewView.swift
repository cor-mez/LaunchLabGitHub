//
//  DotTestPreviewView.swift
//

import MetalKit
import UIKit

@MainActor
final class DotTestPreviewView: MTKView {

    private var currentTexture: MTLTexture?
    private var currentIsR8: Bool = false
    private var currentForceSolid: Bool = false

    // 🔵 Debug overlay
    private let overlayLayer = DotTestOverlayLayer()

    // MARK: - Init ------------------------------------------------------------

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

        // 🔵 Attach overlay ABOVE Metal content
        overlayLayer.contentsScale = UIScreen.main.scale
        overlayLayer.isOpaque = false
        layer.addSublayer(overlayLayer)
    }

    // MARK: - Layout ----------------------------------------------------------

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayLayer.frame = bounds
    }

    // MARK: - Render API ------------------------------------------------------

    func render(
        texture: MTLTexture?,
        isR8: Bool,
        forceSolidColor: Bool
    ) {
        currentTexture = texture
        currentIsR8 = isR8
        currentForceSolid = forceSolidColor
    }

    // MARK: - Overlay Update --------------------------------------------------

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

// -----------------------------------------------------------------------------
// MARK: - MTKViewDelegate
// -----------------------------------------------------------------------------

extension DotTestPreviewView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        MetalRenderer.shared.renderPreview(
            texture: currentTexture,
            in: self,
            isR8: currentIsR8,
            forceSolid: currentForceSolid
        )
    }
}
