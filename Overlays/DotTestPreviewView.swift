import UIKit
import MetalKit
import CoreGraphics

final class DotTestPreviewView: MTKView {

    private let coordinator = DotTestCoordinator.shared
    private let overlay = DotTestOverlayLayer()

    var debugSurface: DotTestDebugSurface = .yNorm
    var roi: CGRect = .zero

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MetalRenderer.shared.device)
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        layer.addSublayer(overlay)
        overlay.frame = bounds
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MetalRenderer.shared.device
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        layer.addSublayer(overlay)
        overlay.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
    }

    func updateDebugSurface(_ surface: DotTestDebugSurface) {
        debugSurface = surface
        setNeedsDisplay()
    }

    func updateROI(_ r: CGRect) {
        roi = r
        overlay.updateROI(r)
        setNeedsDisplay()
    }

    func refreshCorners() {
        overlay.updateAllCorners()
    }

    override func draw(_ rect: CGRect) {
        coordinator.draw(in: self, surface: debugSurface)
        overlay.setNeedsDisplay()
    }
}