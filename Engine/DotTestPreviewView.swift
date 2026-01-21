// DotTestPreviewView.swift
// LaunchLab
//
// Minimal MTKView wrapper for live camera preview.
// OBSERVABILITY ONLY.
//

import MetalKit

@MainActor
final class DotTestPreviewView: MTKView {

    init(frame: CGRect, device: MTLDevice) {
        super.init(frame: frame, device: device)

        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        enableSetNeedsDisplay = false
        isPaused = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(texture: MTLTexture) {
        MetalRenderer.shared.renderPreview(
            texture: texture,
            in: self
        )
    }
}
