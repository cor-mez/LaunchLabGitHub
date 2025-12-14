// DotTestOverlayLayer.swift

import UIKit
import CoreGraphics

@MainActor
final class DotTestOverlayLayer: CALayer {

    private let mode = DotTestMode.shared

    private var fullSize: CGSize = .zero
    private var roiRect: CGRect = .zero
    private var srScale: CGFloat = 1.0

    override func draw(in ctx: CGContext) {

        // Safety: never draw before system is armed
        guard mode.isArmedForDetection else { return }

        // Safety: wait for warmup frames
        guard mode.warmupFrameCount >= mode.warmupFramesNeeded else { return }

        // Valid frame geometry required
        guard fullSize.width > 32, fullSize.height > 32 else { return }
        guard roiRect.width > 4, roiRect.height > 4 else { return }

        let matches = mode.matchCorners
        let cpuOnly = mode.cpuOnlyCorners
        let gpuOnly = mode.gpuOnlyCorners
        let vectors = mode.mismatchVectors

        let sx = bounds.width / fullSize.width
        let sy = bounds.height / fullSize.height

        func xf(_ p: CGPoint) -> CGPoint {
            let rx = roiRect.origin.x + p.x / srScale
            let ry = roiRect.origin.y + p.y / srScale
            return CGPoint(x: rx * sx, y: ry * sy)
        }

        // DRAW MATCHES (white)
        ctx.setFillColor(UIColor.white.cgColor)
        for p in matches {
            let q = xf(p)
            ctx.fillEllipse(in: CGRect(x: q.x - 2,
                                       y: q.y - 2,
                                       width: 4,
                                       height: 4))
        }

        // DRAW CPU-ONLY (green)
        ctx.setFillColor(UIColor.green.cgColor)
        for p in cpuOnly {
            let q = xf(p)
            ctx.fillEllipse(in: CGRect(x: q.x - 2,
                                       y: q.y - 2,
                                       width: 4,
                                       height: 4))
        }

        // DRAW GPU-ONLY (red)
        ctx.setFillColor(UIColor.red.cgColor)
        for p in gpuOnly {
            let q = xf(p)
            ctx.fillEllipse(in: CGRect(x: q.x - 2,
                                       y: q.y - 2,
                                       width: 4,
                                       height: 4))
        }

        // DRAW mismatch vectors
        if mode.showVectors {
            ctx.setStrokeColor(UIColor.purple.cgColor)
            ctx.setLineWidth(1.0)

            for (cpuPoint, gpuPoint) in vectors {
                let c = xf(cpuPoint)
                let g = xf(gpuPoint)
                ctx.move(to: c)
                ctx.addLine(to: g)
                ctx.strokePath()
            }
        }
    }

    func update(fullSize: CGSize,
                roi: CGRect,
                sr: CGFloat) {

        self.fullSize = fullSize
        self.roiRect = roi
        self.srScale = sr

        // NOTE: safe because layer is @MainActor
        setNeedsDisplay()
    }
}
