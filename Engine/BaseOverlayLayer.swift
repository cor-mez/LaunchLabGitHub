// File: Overlays/BaseOverlayLayer.swift
//  BaseOverlayLayer.swift
//  LaunchLab
//

import UIKit

class BaseOverlayLayer: CALayer {

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true   // <-- CRITICAL
        setNeedsDisplay()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    /// Per-frame mapper injection (buffer → view coordinates).
    /// Subclasses may override to store mapper.
    func assignMapper(_ mapper: OverlayMapper) {
        _ = mapper
    }

    /// Per-frame vision data injection.
    /// Subclasses may override to store frame.
    func updateWithFrame(_ frame: VisionFrameData) {
        _ = frame
    }

    /// Ensure layer draws only when a valid context exists.
    override func draw(in ctx: CGContext) {
        let w = ctx.width
        let h = ctx.height

        // Allow small contexts, block only 0×0
        if w == 0 || h == 0 { return }

        // Child layers override this; nothing drawn here.
    }
}
