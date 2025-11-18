//
//  RPEOverlayLayer.swift
//  LaunchLab
//

import Foundation
import QuartzCore
import CoreGraphics
import UIKit
import simd

final class RPEOverlayLayer: CALayer {

    private var frameData: VisionFrameData?

    public func update(frame: VisionFrameData) {
        self.frameData = frame
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        guard let frame = frameData else { return }
        guard let pose = frame.pose else { return }

        let R = pose.R
        let T = pose.T
        let K = frame.intrinsics.matrix

        let viewSize = bounds.size
        let bufferW = frame.width
        let bufferH = frame.height

        var errors: [Float] = []

        // ---------------------------------------------------------
        // Draw for each dot
        // ---------------------------------------------------------
        for dot in frame.dots {
            let id = dot.id
            let Xw = DotModel().point(for: id)

            // Camera coordinates
            let Xc = R * Xw + T
            if Xc.z <= 1e-6 { continue }

            // Projected pixel
            let projPix = PoseSolver.projectPoint(Xc, intrinsics: K)
            let projCG = CGPoint(x: CGFloat(projPix.x), y: CGFloat(projPix.y))

            // Observed pixel
            let obs = dot.position

            // Map to view coordinates
            let projView = VisionOverlaySupport.mapPointFromBufferToView(
                point: projCG,
                bufferWidth: bufferW,
                bufferHeight: bufferH,
                viewSize: viewSize
            )

            let obsView = VisionOverlaySupport.mapPointFromBufferToView(
                point: obs,
                bufferWidth: bufferW,
                bufferHeight: bufferH,
                viewSize: viewSize
            )

            let dx = Float(obs.x - CGFloat(projPix.x))
            let dy = Float(obs.y - CGFloat(projPix.y))
            let e = sqrt(dx*dx + dy*dy)
            errors.append(e)

            // Color encode error
            let color = rpeColor(magnitude: CGFloat(e))

            // Draw projected dot
            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: projView,
                radius: 3,
                color: UIColor.white.withAlphaComponent(0.7).cgColor
            )

            // Draw observed dot
            VisionOverlaySupport.drawCircle(
                context: ctx,
                at: obsView,
                radius: 3,
                color: color
            )

            // Draw residual vector
            ctx.setStrokeColor(color)
            ctx.setLineWidth(1.2)
            ctx.beginPath()
            ctx.move(to: projView)
            ctx.addLine(to: obsView)
            ctx.strokePath()
        }

        // ---------------------------------------------------------
        // Draw text HUD
        // ---------------------------------------------------------
        if !errors.isEmpty {
            let rms = sqrt(errors.reduce(0){$0 + $1*$1} / Float(errors.count))
            let maxErr = errors.max() ?? 0
            let inliers = errors.filter { $0 < 5 }.count
            let outliers = errors.count - inliers

            let text =
            String(format: "RPE: %.2f px RMS\nMax: %.2f px\nInliers: %d\nOutliers: %d",
                   rms, maxErr, inliers, outliers)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white,
            ]

            text.draw(
                with: CGRect(x: 8, y: 8, width: 240, height: 80),
                options: .usesLineFragmentOrigin,
                attributes: attrs,
                context: nil
            )
        }
    }

    // ---------------------------------------------------------
    // MARK: - Color Mapping
    // ---------------------------------------------------------
    private func rpeColor(magnitude e: CGFloat) -> CGColor {
        switch e {
        case 0..<2:   return UIColor.green.withAlphaComponent(0.9).cgColor
        case 2..<5:   return UIColor.yellow.withAlphaComponent(0.9).cgColor
        default:      return UIColor.red.withAlphaComponent(0.9).cgColor
        }
    }
}