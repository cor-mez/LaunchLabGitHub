//
//  SpinAxisOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import UIKit
import simd

final class SpinAxisOverlayLayer: CALayer {

    private var frameData: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Public Update
    // ---------------------------------------------------------
    public func update(frame: VisionFrameData) {
        self.frameData = frame
        setNeedsDisplay()
    }

    // ---------------------------------------------------------
    // MARK: - Draw
    // ---------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let frame = frameData else { return }
        guard let spin = frame.spin else { return }

        let w = spin.axis
        if simd_length(w) < 1e-6 { return }

        let K = frame.intrinsics.matrix
        let size = bounds.size

        // -----------------------------------------------------
        // 1) Compute center of image in view space
        // -----------------------------------------------------
        let cxView = size.width * 0.5
        let cyView = size.height * 0.5

        // -----------------------------------------------------
        // 2) Perspective projection of direction vector
        //    Use axis direction as 3D ray, normalize, project
        // -----------------------------------------------------
        var d = normalize(w)
        if abs(d.z) < 1e-5 { d.z = 1e-5 }

        let px = (K[0,0] * (d.x / d.z)) + K[0,2]
        let py = (K[1,1] * (d.y / d.z)) + K[1,2]

        // Map from buffer → view
        let projected = VisionOverlaySupport.mapPointFromBufferToView(
            point: CGPoint(x: CGFloat(px), y: CGFloat(py)),
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: size
        )

        let start = CGPoint(x: cxView, y: cyView)
        let end = projected

        // -----------------------------------------------------
        // 3) Draw arrow
        // -----------------------------------------------------
        ctx.setStrokeColor(UIColor.systemOrange.cgColor)
        ctx.setLineWidth(2.0)
        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Arrowhead
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)

        let arrowLen: CGFloat = 10
        let left = CGPoint(
            x: end.x - arrowLen * cos(angle - .pi/6),
            y: end.y - arrowLen * sin(angle - .pi/6)
        )
        let right = CGPoint(
            x: end.x - arrowLen * cos(angle + .pi/6),
            y: end.y - arrowLen * sin(angle + .pi/6)
        )

        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.move(to: end)
        ctx.addLine(to: right)
        ctx.strokePath()

        // -----------------------------------------------------
        // 4) Draw RPM text
        // -----------------------------------------------------
        let text = String(format: "Spin: %.0f RPM", spin.rpm)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.systemOrange
        ]
        text.draw(at: CGPoint(x: 12, y: 12), withAttributes: attrs)
    }
}