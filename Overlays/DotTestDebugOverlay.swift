import UIKit

final class DotTestDebugOverlay: CALayer {

    private var cpuPoints: [CGPoint] = []
    private var gpuPoints: [CGPoint] = []
    private var roiRect: CGRect = .zero
    private var bufferSize: CGSize = .zero

    func update(pointsCPU: [CGPoint],
                pointsGPU: [CGPoint],
                bufferSize: CGSize,
                roiRect: CGRect?) {
        self.cpuPoints = pointsCPU
        self.gpuPoints = pointsGPU
        self.bufferSize = bufferSize
        self.roiRect = roiRect ?? .zero
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        let w = bufferSize.width
        let h = bufferSize.height
        if w <= 0 || h <= 0 { return }

        let vw = bounds.width
        let vh = bounds.height
        if vw <= 0 || vh <= 0 { return }

        let sx = vw / w
        let sy = vh / h
        let scale = min(sx, sy)

        ctx.setLineWidth(2)

        if roiRect.width > 0 && roiRect.height > 0 {
            ctx.setStrokeColor(UIColor.white.cgColor)
            let x = roiRect.origin.x * scale
            let y = roiRect.origin.y * scale
            let rw = roiRect.width * scale
            let rh = roiRect.height * scale
            ctx.stroke(CGRect(x: x, y: y, width: rw, height: rh))
        }

        ctx.setFillColor(UIColor.yellow.cgColor)
        for p in cpuPoints {
            let x = p.x * scale
            let y = p.y * scale
            let r: CGFloat = 4
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }

        ctx.setStrokeColor(UIColor.cyan.cgColor)
        for p in gpuPoints {
            let x = p.x * scale
            let y = p.y * scale
            let s: CGFloat = 4
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x - s, y: y))
            ctx.addLine(to: CGPoint(x: x + s, y: y))
            ctx.move(to: CGPoint(x: x, y: y - s))
            ctx.addLine(to: CGPoint(x: x, y: y + s))
            ctx.strokePath()
        }
    }
}
