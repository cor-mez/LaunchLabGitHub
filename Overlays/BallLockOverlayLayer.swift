//
//  BallLockOverlayLayer.swift
//  LaunchLab
//
//  Debug overlay for visualizing BallLock / RS-PnP state.
//  Draws a circle in view space and a small text label with quality & state.
//

import UIKit
import CoreGraphics

final class BallLockOverlayLayer: BaseOverlayLayer {

    // MARK: - Visual State

    private enum VisualState {
        case searching   // no dots / no pose
        case locking     // dots present, pose not yet valid
        case locked      // pose is valid
    }

    // Stored properties for current frame
    private var roiCenterPx: CGPoint?
    private var roiRadiusPx: CGFloat = 0
    private var quality: CGFloat = 0
    private var confidence: CGFloat = 0
    private var visualState: VisualState = .searching

    // MARK: - Frame Update

    override func updateWithFrame(_ frame: VisionFrameData) {
        let width  = CGFloat(frame.width)
        let height = CGFloat(frame.height)

        // Default ROI: bottom-center of the image
        var center = CGPoint(x: width / 2.0, y: height * 0.65)

        // If we have RS-corrected points, use their average as the center
        if let corrected = frame.correctedPoints, !corrected.isEmpty {
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            for p in corrected {
                sx += CGFloat(p.corrected.x)
                sy += CGFloat(p.corrected.y)
            }
            let count = CGFloat(corrected.count)
            center = CGPoint(x: sx / count, y: sy / count)
        } else if !frame.dots.isEmpty {
            // Fallback: average raw dot positions
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            for d in frame.dots {
                sx += d.position.x
                sy += d.position.y
            }
            let count = CGFloat(frame.dots.count)
            center = CGPoint(x: sx / count, y: sy / count)
        }

        roiCenterPx = center
        // Simple heuristic radius: ~18% of min dimension, clamped
        roiRadiusPx = max(40.0, min(width, height) * 0.18)

        // Use spin confidence as a "quality" proxy if available
        if let spin = frame.spin {
            quality = CGFloat(spin.confidence)
            confidence = quality
        } else {
            quality = 0
            confidence = 0
        }

        // Infer current visual state from frame content
        if frame.dots.isEmpty {
            visualState = .searching
        } else if let pose = frame.rspnp, pose.isValid {
            // We have a valid RS-PnP solution
            visualState = .locked
        } else {
            // We have some dots but no valid pose yet
            visualState = .locking
        }

        // Trigger a redraw of this layer
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(in ctx: CGContext) {
        guard let mapper = mapper, let centerPx = roiCenterPx else { return }

        // Map ROI center & radius from buffer space to view space
        let centerView = mapper.mapPointFromBufferToView(point: centerPx)
        let edgePx = CGPoint(x: centerPx.x + roiRadiusPx, y: centerPx.y)
        let edgeView = mapper.mapPointFromBufferToView(point: edgePx)
        let radius = hypot(edgeView.x - centerView.x, edgeView.y - centerView.y)
        if radius < 2 { return }

        // Stroke color based on state
        let strokeColor: CGColor
        switch visualState {
        case .searching: strokeColor = UIColor.white.cgColor
        case .locking:   strokeColor = UIColor.systemYellow.cgColor
        case .locked:    strokeColor = UIColor.systemGreen.cgColor
        }

        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(2.0)

        let circleRect = CGRect(
            x: centerView.x - radius,
            y: centerView.y - radius,
            width: radius * 2.0,
            height: radius * 2.0
        )
        ctx.strokeEllipse(in: circleRect)

        // Draw debug text (quality + state code) just above the circle
        let stateIndex: Int
        switch visualState {
        case .searching: stateIndex = 0
        case .locking:   stateIndex = 1
        case .locked:    stateIndex = 2
        }

        let text = String(format: "q: %.2f  s:%d", quality, stateIndex)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: centerView.x - textSize.width / 2.0,
            y: centerView.y - radius - textSize.height - 4.0
        )
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
}
