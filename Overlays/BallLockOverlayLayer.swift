// File: Overlays/BallLockOverlayLayer.swift
//  BallLockOverlayLayer.swift
//  LaunchLab
//
//  Draws the BallLock ROI circle and encodes lock state in color:
//
//    • searching / cooldown  → grey
//    • candidate             → yellow
//    • locked                → green
//

import UIKit

final class BallLockOverlayLayer: BaseOverlayLayer {

    private var latestFrame: VisionFrameData?

    // Store the latest frame each tick
    override func updateWithFrame(_ frame: VisionFrameData) {
        latestFrame = frame
    }

    override func draw(in ctx: CGContext) {
        let w = ctx.width
        let h = ctx.height
        if w == 0 || h == 0 { return }

        guard
            let frame = latestFrame,
            let residuals = frame.residuals,
            let roiResidual = residuals.first(where: { $0.id == 100 })
        else {
            return
        }

        // ROI in pixel space (camera buffer)
        let bufferWidth = CGFloat(frame.width)
        let bufferHeight = CGFloat(frame.height)
        if bufferWidth <= 0 || bufferHeight <= 0 { return }

        let roiCenterPx = CGPoint(
            x: CGFloat(roiResidual.error.x),
            y: CGFloat(roiResidual.error.y)
        )
        let roiRadiusPx = CGFloat(roiResidual.weight)

        // Lock residual: id 101 → (quality, stateCode)
        let lockResidual = residuals.first(where: { $0.id == 101 })
        let stateCode = lockResidual.map { Int($0.error.y) } ?? 0
        // let quality  = lockResidual?.error.x ?? 0  // available if needed

        let isSearching  = (stateCode == 0)
        let isCandidate  = (stateCode == 1)
        let isLocked     = (stateCode == 2)
        let isCooldown   = (stateCode == 3)

        let strokeColor: UIColor
        if isLocked {
            strokeColor = .systemGreen              // final lock
        } else if isCandidate {
            strokeColor = .systemYellow             // “almost locked”
        } else if isSearching || isCooldown {
            strokeColor = UIColor(white: 1.0, alpha: 0.4)
        } else {
            strokeColor = UIColor(white: 1.0, alpha: 0.4)
        }

        // Map buffer pixels → overlay layer points (uniform scale)
        let bounds = self.bounds
        if bounds.width <= 0 || bounds.height <= 0 { return }

        let sx = bounds.width / bufferWidth
        let sy = bounds.height / bufferHeight
        let scale = min(sx, sy)

        let centerView = CGPoint(
            x: roiCenterPx.x * scale,
            y: roiCenterPx.y * scale
        )
        let radiusView = roiRadiusPx * scale

        // Draw circle
        ctx.saveGState()
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(strokeColor.cgColor)

        let rect = CGRect(
            x: centerView.x - radiusView,
            y: centerView.y - radiusView,
            width: radiusView * 2.0,
            height: radiusView * 2.0
        )
        ctx.addEllipse(in: rect)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
