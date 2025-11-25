//
//  RSTimingOverlayLayer.swift
//  LaunchLab
//
//  Stubbed (Model-1 RS Overlay Disabled)
//

import UIKit
import QuartzCore

final class RSTimingOverlayLayer: CALayer {

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(frame: VisionFrameData) {
        // RS timing overlay disabled — no-op
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        // RS timing overlay disabled — no-op
    }
}
