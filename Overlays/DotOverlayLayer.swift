//
//  DotOverlayLayer.swift
//  LaunchLab
//

import UIKit

final class DotOverlayLayer: CALayer {

    weak var camera: CameraManager?

    override func draw(in ctx: CGContext) {
        guard let camera else { return }

        let frame = MainActor.assumeIsolated {
            camera.latestFrame
        }

        guard let frame else { return }
        ctx.setFillColor(UIColor.red.cgColor)

        for dot in frame.dots {
            let p = dot.position
            let r: CGFloat = 4

            ctx.fillEllipse(in: CGRect(
                x: p.x - r,
                y: p.y - r,
                width: r * 2,
                height: r * 2
            ))
        }
    }
}
