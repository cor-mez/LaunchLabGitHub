//
//  HUDOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class HUDOverlayLayer: BaseOverlayLayer {

    private var frameData: VisionFrameData?

    override func updateWithFrame(_ frame: VisionFrameData) {
        frameData = frame
        setNeedsDisplay()
    }

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        guard let f = frameData else { return }

        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attrs: [NSAttributedString.Key:Any] =
            [.font: font, .foregroundColor: UIColor.green]

        "t = \(String(format: "%.4f", f.timestamp))"
            .draw(at: CGPoint(x: 10, y: 10), withAttributes: attrs)

        "dots = \(f.dots.count)"
            .draw(at: CGPoint(x: 10, y: 28), withAttributes: attrs)
    }
}
