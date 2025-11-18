//
//  PerformanceHUDLayer.swift
//  LaunchLab
//

import UIKit
import CoreGraphics
import simd

final class PerformanceHUDLayer: CALayer {

    // Latest frame from CameraManager
    weak var latestFrame: VisionFrameData?

    // FPS estimation
    private var lastTimestamp: CFTimeInterval = 0
    private var fpsSamples: [Double] = Array(repeating: 0, count: 30)
    private var fpsIndex = 0
    private var fpsFilled = false

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
        drawsAsynchronously = false
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = latestFrame else { return }

        // --- FPS tracking ---
        let now = frame.timestamp
        if lastTimestamp > 0 {
            let dt = now - lastTimestamp
            if dt > 0 {
                let fps = 1.0 / dt
                fpsSamples[fpsIndex] = fps
                fpsIndex = (fpsIndex + 1) % 30
                if fpsIndex == 0 { fpsFilled = true }
            }
        }
        lastTimestamp = now

        let fpsCount = fpsFilled ? 30 : fpsIndex
        let fpsAvg = fpsCount > 0 ? fpsSamples.prefix(fpsCount).reduce(0,+)/Double(fpsCount) : 0

        let prof = FrameProfiler.shared.visualMetrics()
        let dotCount = frame.dots.count
        let poseRMS = frame.pose?.reprojectionError ?? 0

        // Intrinsics debug
        let i = frame.intrinsics
        let intrinsicsText = "fx:\(Int(i.fx)) fy:\(Int(i.fy)) cx:\(Int(i.cx)) cy:\(Int(i.cy))"

        let text =
        """
        FPS: \(String(format:"%.1f", fpsAvg))
        DOTS: \(dotCount)
        POSE RMS: \(String(format:"%.2f", poseRMS))

        CPU (avg ms):
          detect:   \(prof.detector)
          track:    \(prof.tracker)
          lk:       \(prof.lk)
          velocity: \(prof.velocity)
          pose:     \(prof.pose)
          total:    \(prof.total)

        GPU (LK):
          last: \(prof.gpuLast) ms
          avg : \(prof.gpuAvg) ms

        INTRINSICS:
          \(intrinsicsText)
        """

        // Background panel
        ctx.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: 8, y: 8, width: 260, height: 260))

        // Text drawing
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.green,
            .paragraphStyle: paragraph
        ]

        text.draw(in: CGRect(x: 16, y: 16, width: 240, height: 240), withAttributes: attrs)
    }

    // Must be called every frame
    func update(with frame: VisionFrameData) {
        self.latestFrame = frame
        setNeedsDisplay()
    }
}