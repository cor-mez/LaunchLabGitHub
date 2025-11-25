//
//  KLTDebugOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore

final class KLTDebugOverlayLayer: BaseOverlayLayer {

    private var currentFrame: VisionFrameData?

    override func updateWithFrame(_ frame: VisionFrameData) {
        self.currentFrame = frame
        setNeedsDisplay()
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        // KLT debug disabled — draws nothing
    }
}
