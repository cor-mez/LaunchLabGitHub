//
//  HUDOverlayLayer.swift
//  LaunchLab
//

import UIKit
import CoreGraphics

final class HUDOverlayLayer: CALayer {

    weak var camera: CameraManager?

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let cam = camera else { return }

        // Pull profiling data
        let metrics = FrameProfiler.shared.visualMetrics()

        let text = """
        CPU:
          detector: \(metrics.detector)
          tracker: \(metrics.tracker)
          lk: \(metrics.lk)
          velocity: \(metrics.velocity)
          pose: \(metrics.pose)
          total: \(metrics.total)

        GPU (LK wrapper):
          last: \(metrics.gpuLast)
          avg : \(metrics.gpuAvg)
        """

        ctx.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: 8, y: 8, width: 260, height: 180))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.green,
            .paragraphStyle: paragraph
        ]

        text.draw(in: CGRect(x: 16, y: 16, width: 240, height: 160), withAttributes: attrs)
    }
}