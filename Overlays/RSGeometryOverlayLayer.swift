//
//  RSGeometryOverlayLayer.swift
//  LaunchLab
//

import UIKit
import QuartzCore
import simd

final class RSGeometryOverlayLayer: CALayer {

    private var corrected: [RSCorrectedPoint] = []
    private var baseR: simd_float3x3 = simd_float3x3(diagonal: SIMD3<Float>(1,1,1))
    private var baseT: SIMD3<Float> = .zero
    private var intrinsics: simd_float3x3 = simd_float3x3(diagonal: SIMD3<Float>(1,1,1))

    private var avgShift: Float = 0

    override init() {
        super.init()
        contentsScale = UIScreen.main.scale
        isOpaque = false
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(frame: VisionFrameData) {

        corrected = frame.rsCorrected
        intrinsics = frame.intrinsics.matrix

        if let p = frame.pose {
            baseR = p.R
            baseT = p.T
        }

        if !corrected.isEmpty {
            var sum: Float = 0
            for c in corrected {
                let baseProj = PoseSolver.projectPoint(
                    point: c.modelPoint,
                    R: baseR,
                    T: baseT,
                    K: intrinsics
                )
                let dx = baseProj.x - c.imagePoint.x
                let dy = baseProj.y - c.imagePoint.y
                sum += sqrt(dx*dx + dy*dy)
            }
            avgShift = sum / Float(corrected.count)
        } else {
            avgShift = 0
        }

        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        ctx.clear(bounds)

        guard !corrected.isEmpty else {
            drawHUD(ctx: ctx)
            return
        }

        for c in corrected {
            let correctedPt = CGPoint(x: CGFloat(c.imagePoint.x),
                                      y: CGFloat(c.imagePoint.y))

            let baseProj = PoseSolver.projectPoint(
                point: c.modelPoint,
                R: baseR,
                T: baseT,
                K: intrinsics
            )

            let basePt = CGPoint(x: CGFloat(baseProj.x),
                                 y: CGFloat(baseProj.y))

            let viewCorrected = VisionOverlaySupport.mapPointFromBufferToView(correctedPt, viewFrame: bounds)
            let viewBase = VisionOverlaySupport.mapPointFromBufferToView(basePt, viewFrame: bounds)

            let dx = Float(basePt.x - correctedPt.x)
            let dy = Float(basePt.y - correctedPt.y)
            let mag = sqrt(dx*dx + dy*dy)

            let color = CGColor(
                red: CGFloat(min(1, mag / 3)),
                green: CGFloat(max(0, 1 - mag / 3)),
                blue: 0,
                alpha: 1
            )

            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(color)

            ctx.beginPath()
            ctx.move(to: viewBase)
            ctx.addLine(to: viewCorrected)
            ctx.strokePath()

            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: viewCorrected.x - 2,
                                       y: viewCorrected.y - 2,
                                       width: 4, height: 4))
        }

        drawHUD(ctx: ctx)
    }

    private func drawHUD(ctx: CGContext) {
        let hud = String(format: "RS Δavg: %.2f px", avgShift)

        let attr: [NSAttributedString.Key : Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let str = NSAttributedString(string: hud, attributes: attr)

        let size = str.size()
        let rect = CGRect(x: 8, y: 8, width: size.width, height: size.height)

        UIGraphicsPushContext(ctx)
        str.draw(in: rect)
        UIGraphicsPopContext()
    }
}