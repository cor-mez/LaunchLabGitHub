//
//  RSTimingCalibrationOverlay.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class RSTimingCalibrationOverlay: CALayer {

    private var samples: [RSTimingSample] = []
    private var curve: [Float] = []
    private var readout: Float = 0.0039
    private var maxRow: Float = 1

    override init() {
        super.init()
        isOpaque = false
        contentsScale = UIScreen.main.scale
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func update(samples: [RSTimingSample],
                curve: [Float],
                readout: Float,
                maxRow: Float)
    {
        self.samples = samples
        self.curve = curve
        self.readout = readout
        self.maxRow = maxRow
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.clear(bounds)

        guard !samples.isEmpty else {
            drawHUD(ctx)
            return
        }

        drawSamples(ctx)
        drawCurvePlot(ctx)
        drawHUD(ctx)
    }

    private func drawSamples(_ ctx: CGContext) {
        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))

        for s in samples {
            let y = CGFloat(s.barRow / maxRow) * bounds.height

            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            ctx.strokePath()

            ctx.setFillColor(CGColor(red: 0, green: 1, blue: 1, alpha: 0.8))
            ctx.fillEllipse(in: CGRect(x: bounds.width * 0.5 - 3,
                                       y: y - 3,
                                       width: 6,
                                       height: 6))
        }
    }

    private func drawCurvePlot(_ ctx: CGContext) {
        guard curve.count > 1 else { return }

        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.9))

        let n = curve.count
        let step = bounds.width / CGFloat(max(1, n - 1))

        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0,
                             y: CGFloat(1 - curve[0]) * bounds.height))

        for i in 1..<n {
            let x = CGFloat(i) * step
            let y = CGFloat(1 - curve[i]) * bounds.height
            ctx.addLine(to: CGPoint(x: x, y: y))
        }

        ctx.strokePath()
    }

    private func drawHUD(_ ctx: CGContext) {
        let text = "Samples: \(samples.count)  Readout: \(String(format: "%.4f", readout))s"
        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white
        ]

        let str = NSAttributedString(string: text, attributes: attr)
        let size = str.size()
        let rect = CGRect(x: 8, y: 8, width: size.width, height: size.height)

        UIGraphicsPushContext(ctx)
        str.draw(in: rect)
        UIGraphicsPopContext()
    }
}