import UIKit
import CoreGraphics

final class DotTestOverlayLayer: CALayer {

    private let coordinator = DotTestCoordinator.shared

    private var cpuCorners: [CGPoint] = []
    private var gpuYCorners: [CGPoint] = []
    private var gpuCbCorners: [CGPoint] = []

    private var roiRect: CGRect = .zero

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func updateAllCorners() {
        cpuCorners = coordinator.cpuCorners()
        gpuYCorners = coordinator.gpuCornersY()
        gpuCbCorners = coordinator.gpuCornersCb()
        setNeedsDisplay()
    }

    func updateROI(_ roi: CGRect) {
        roiRect = roi
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.setFillColor(UIColor.green.cgColor)
        let s: CGFloat = 3.0
        for p in cpuCorners {
            let r = CGRect(x: p.x - s*0.5,
                           y: p.y - s*0.5,
                           width: s,
                           height: s)
            ctx.fillEllipse(in: r)
        }

        ctx.setFillColor(UIColor.red.cgColor)
        for p in gpuYCorners {
            let r = CGRect(x: p.x - s*0.5,
                           y: p.y - s*0.5,
                           width: s,
                           height: s)
            ctx.fillEllipse(in: r)
        }

        ctx.setFillColor(UIColor.blue.cgColor)
        for p in gpuCbCorners {
            let r = CGRect(x: p.x - s*0.5,
                           y: p.y - s*0.5,
                           width: s,
                           height: s)
            ctx.fillEllipse(in: r)
        }

        if roiRect != .zero {
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(roiRect)
        }
    }
}