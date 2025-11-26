// File: Overlays/OverlayView.swift

import UIKit

final class OverlayView: UIView {

    private let layers: [BaseOverlayLayer]

    init(layers: [BaseOverlayLayer]) {
        self.layers = layers
        super.init(frame: .zero)
        isOpaque = false

        // Add layers to the view
        for layer in layers {
            layer.frame = bounds           // <-- initial sizing
            self.layer.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // CRITICAL FIX:
        // Resize all overlay layers to match the view's bounds EVERY frame.
        for layer in layers {
            layer.frame = bounds
            layer.setNeedsDisplay()       // REQUIRED to trigger draw(in:)
        }
    }
}
