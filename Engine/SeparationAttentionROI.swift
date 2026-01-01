//
//  SeparationAttentionROI.swift
//  LaunchLab
//
//  Defines a directional, impact-conditioned attention region
//  for observing post-impact separation without texture discovery.
//

import CoreGraphics
import Foundation

struct SeparationAttentionROI {

    let rect: CGRect
    let direction: CGVector

    static func make(
        impactCenter: CGPoint,
        direction: CGVector,
        fullSize: CGSize,
        length: CGFloat = 300,
        halfWidth: CGFloat = 40
    ) -> SeparationAttentionROI? {

        let mag = hypot(direction.dx, direction.dy)
        guard mag > 1e-6 else { return nil }

        let ux = direction.dx / mag
        let uy = direction.dy / mag

        // Build a rectangle extending *forward* from impact
        let cx = impactCenter.x + ux * length * 0.5
        let cy = impactCenter.y + uy * length * 0.5

        let rect = CGRect(
            x: cx - length * 0.5,
            y: cy - halfWidth,
            width: length,
            height: halfWidth * 2
        ).integral

        // Clamp to frame
        let clamped = rect.intersection(
            CGRect(origin: .zero, size: fullSize)
        )

        guard clamped.width > 8, clamped.height > 8 else { return nil }

        return SeparationAttentionROI(
            rect: clamped,
            direction: CGVector(dx: ux, dy: uy)
        )
    }
}
