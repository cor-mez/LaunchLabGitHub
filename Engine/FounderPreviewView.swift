//
//  FounderPreviewView.swift
//  LaunchLab
//
//  Live camera preview (OBSERVABILITY ONLY)
//  - Single-present Metal rendering
//  - Camera drives texture updates
//  - MTKView draws ONLY on explicit request
//  - No authority, no inference
//

import MetalKit
import CoreVideo

@MainActor
final class FounderPreviewView: MTKView {

    // ---------------------------------------------------------------------
    // MARK: - State
    // ---------------------------------------------------------------------

    /// Current Y-plane texture for preview
    private var currentTexture: MTLTexture?

    // ---------------------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------------------

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)

        framebufferOnly = false

        // 🔑 CRITICAL:
        // Disable automatic rendering.
        // We explicitly request draws when a new frame arrives.
        isPaused = true
        enableSetNeedsDisplay = true

        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // ---------------------------------------------------------------------
    // MARK: - Frame ingestion (from CameraCapture)
    // ---------------------------------------------------------------------

    /// Update preview texture and request exactly one draw.
    /// Called from camera callback.
    func update(pixelBuffer: CVPixelBuffer) {

        currentTexture = MetalRenderer.shared.makeYPlaneTexture(from: pixelBuffer)

        // 🔑 Exactly ONE draw per frame
        setNeedsDisplay()
    }
}

// -----------------------------------------------------------------------------
// MARK: - MTKViewDelegate
// -----------------------------------------------------------------------------

extension FounderPreviewView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No-op
    }

    func draw(in view: MTKView) {

        guard DotTestMode.shared.previewEnabled else { return }
        guard let tex = currentTexture else { return }

        MetalRenderer.shared.renderPreview(
            texture: tex,
            in: view
        )
    }
}
