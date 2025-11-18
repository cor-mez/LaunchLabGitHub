//
//  VelocityOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class VelocityOverlayLayer: CALayer {

    weak var camera: CameraManager?

    override func draw(in ctx: CGContext) {
        guard let camera else { return }

        // MainActor hop to safely read @Published latestFrame
        let frame = MainActor.assumeIsolated {
            camera.latestFrame
        }

        guard let frame else { return }

        ctx.setLineWidth(2)
        ctx.setStrokeColor(UIColor.cyan.cgColor)

        for dot in frame.dots {
            guard let v = dot.velocity else { continue }

            let p = dot.position
            let end = CGPoint(
                x: p.x + CGFloat(v.dx) * 0.5,
                y: p.y + CGFloat(v.dy) * 0.5
            )

            ctx.move(to: p)
            ctx.addLine(to: end)
            ctx.strokePath()
        }
    }
}
