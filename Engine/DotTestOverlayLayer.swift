//
//  DotTestOverlayLayer.swift
//

import UIKit
import CoreGraphics

@MainActor
final class DotTestOverlayLayer: CALayer {

    private let mode = DotTestMode.shared

    // Cached transforms
    private var fullSize: CGSize = .zero
    private var roi: CGRect      = .zero
    private var srScale: CGFloat = 1.0

    // MARK: - External Update API --------------------------------------------

    func update(fullSize: CGSize, roi: CGRect, sr: CGFloat) {
        self.fullSize = fullSize
        self.roi      = roi
        self.srScale  = sr
        setNeedsDisplay()
    }

    // MARK: - Mapping Helpers -------------------------------------------------

    private func roiRectInView() -> CGRect {
        guard fullSize.width > 0, fullSize.height > 0 else { return .zero }

        let viewW = bounds.width
        let viewH = bounds.height

        let sx = viewW / fullSize.width
        let sy = viewH / fullSize.height
        let scale = min(sx, sy)

        let rw = roi.width  * scale
        let rh = roi.height * scale
        let rx = roi.origin.x * scale
        let ry = roi.origin.y * scale

        return CGRect(x: rx, y: ry, width: rw, height: rh)
    }

    private func mapPoint(
        _ p: CGPoint,
        roiView: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: roiView.origin.x + p.x * scaleX,
            y: roiView.origin.y + p.y * scaleY
        )
    }

    // MARK: - Drawing ----------------------------------------------------------

    override func draw(in ctx: CGContext) {
        guard roi.width > 0, roi.height > 0 else { return }

        let roiView = roiRectInView()

        // Scale from ROI space → view space
        let sx = roiView.width  / roi.width
        let sy = roiView.height / roi.height

        // 🔵 ROI CIRCLE (DEBUG)
        drawROICircle(in: ctx, roiView: roiView)

        drawMatches(in: ctx, rect: roiView, sx: sx, sy: sy)
        drawCPUOnly(in: ctx, rect: roiView, sx: sx, sy: sy)
        drawGPUOnly(in: ctx, rect: roiView, sx: sx, sy: sy)
        drawVectors(in: ctx, rect: roiView, sx: sx, sy: sy)
    }

    // MARK: - ROI Circle -------------------------------------------------------

    private func drawROICircle(in ctx: CGContext, roiView: CGRect) {
        let center = CGPoint(
            x: roiView.midX,
            y: roiView.midY
        )

        let radius = min(roiView.width, roiView.height) * 0.5

        ctx.setStrokeColor(UIColor.cyan.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineDash(phase: 0, lengths: [6, 4]) // dashed = clearly debug

        ctx.strokeEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )

        ctx.setLineDash(phase: 0, lengths: []) // reset
    }

    // MARK: - Corner Drawing ---------------------------------------------------

    private func drawMatches(
        in ctx: CGContext,
        rect: CGRect,
        sx: CGFloat,
        sy: CGFloat
    ) {
        ctx.setFillColor(UIColor.white.cgColor)

        for p in mode.matchCorners {
            let v = mapPoint(p, roiView: rect, scaleX: sx, scaleY: sy)
            ctx.fillEllipse(in: CGRect(x: v.x - 2, y: v.y - 2, width: 4, height: 4))
        }
    }

    private func drawCPUOnly(
        in ctx: CGContext,
        rect: CGRect,
        sx: CGFloat,
        sy: CGFloat
    ) {
        ctx.setFillColor(UIColor.green.cgColor)

        for p in mode.cpuOnlyCorners {
            let v = mapPoint(p, roiView: rect, scaleX: sx, scaleY: sy)
            ctx.fillEllipse(in: CGRect(x: v.x - 2, y: v.y - 2, width: 4, height: 4))
        }
    }

    private func drawGPUOnly(
        in ctx: CGContext,
        rect: CGRect,
        sx: CGFloat,
        sy: CGFloat
    ) {
        ctx.setFillColor(UIColor.red.cgColor)

        for p in mode.gpuOnlyCorners {
            let v = mapPoint(p, roiView: rect, scaleX: sx, scaleY: sy)
            ctx.fillEllipse(in: CGRect(x: v.x - 2, y: v.y - 2, width: 4, height: 4))
        }
    }

    // MARK: - Mismatch Vectors -------------------------------------------------

    private func drawVectors(
        in ctx: CGContext,
        rect: CGRect,
        sx: CGFloat,
        sy: CGFloat
    ) {
        guard mode.showVectors else { return }

        ctx.setStrokeColor(UIColor.purple.cgColor)
        ctx.setLineWidth(1.5)

        for pair in mode.mismatchVectors {
            let c = mapPoint(pair.0, roiView: rect, scaleX: sx, scaleY: sy)
            let g = mapPoint(pair.1, roiView: rect, scaleX: sx, scaleY: sy)

            ctx.move(to: c)
            ctx.addLine(to: g)
            ctx.strokePath()
        }
    }
}
