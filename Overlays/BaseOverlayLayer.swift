// File: Vision/Overlays/BaseOverlayLayer.swift
//
//  Common base class for overlay CALayers.
//  Subclasses override `updateWithFrame(_:)` and `drawOverlay(in:mapper:)`.
//

import UIKit
import CoreGraphics

class BaseOverlayLayer: CALayer {

    /// Mapper from buffer space → view space, injected by `PreviewView`.
    internal private(set) var mapper: OverlayMapper?

    // MARK: - Init

    override init() {
        super.init()
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    // MARK: - Public API

    func updateWithFrame(_ frame: VisionFrameData) {
        // Default: no-op
    }

    @discardableResult
    internal func assignMapper(_ mapper: OverlayMapper) -> Self {
        self.mapper = mapper
        setNeedsDisplay()
        return self
    }

    // MARK: - Drawing

    override func draw(in ctx: CGContext) {
        guard let mapper = mapper else { return }

        // Make UIKit text drawing see THIS CoreGraphics context.
        UIGraphicsPushContext(ctx)
        drawOverlay(in: ctx, mapper: mapper)
        UIGraphicsPopContext()
    }

    func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        // Default: no-op
    }
}
