// File: Vision/Overlays/BallLockDebugOverlayLayer.swift
// BallLockDebugOverlayLayer v2 — topmost BallLock visualization overlay.
// Reads BallLock data from RPEResiduals (IDs 100/101/102[/103]) and VisionFrameData.dots.
// Uses BallLockConfig for toggles. No changes to VisionTypes.swift.

import UIKit
import QuartzCore

final class BallLockDebugOverlayLayer: BaseOverlayLayer {

    weak var ballLockConfig: BallLockConfig?

    // Latest ROI / metrics in buffer-space coordinates
    private var roiCenterBuffer: CGPoint?
    private var roiRadiusPx: CGFloat?
    private var quality: CGFloat = 0
    private var symmetry: CGFloat = 0
    private var count: Int = 0
    private var radiusPx: CGFloat = 0
    private var stateCode: Int = 0
    private var confidence: CGFloat = 0

    private var clusterDots: [CGPoint] = []

    // Breadcrumb of last N ROI centers (buffer space)
    private var breadcrumb: [CGPoint] = []
    private let breadcrumbCapacity: Int = 20

    // MARK: - Public API

    override func updateWithFrame(_ frame: VisionFrameData) {
        guard let residuals = frame.residuals else {
            return
        }

        var newCenter: CGPoint?
        var newRadius: CGFloat?
        var newQuality: CGFloat = 0
        var newSymmetry: CGFloat = 0
        var newCount: Int = 0
        var newRadiusPx: CGFloat = 0
        var newStateCode: Int = 0
        var newConfidence: CGFloat = 0

        // Cluster dots from VisionFrameData (ball-only when locked).
        clusterDots.removeAll(keepingCapacity: true)
        for d in frame.dots {
            clusterDots.append(d.position)
        }

        for residual in residuals {
            switch residual.id {
            case 100:
                // ROI center / radius
                newCenter = CGPoint(
                    x: CGFloat(residual.error.x),
                    y: CGFloat(residual.error.y)
                )
                newRadius = CGFloat(residual.weight)

            case 101:
                // Quality / state / confidence
                newQuality = CGFloat(residual.error.x)
                newStateCode = Int(residual.error.y)
                newConfidence = CGFloat(residual.weight)

            case 102:
                // Symmetry / radiusPx / count
                newSymmetry = CGFloat(residual.error.x)
                newRadiusPx = CGFloat(residual.error.y)
                newCount = Int(residual.weight)

            default:
                continue
            }
        }

        roiCenterBuffer = newCenter
        roiRadiusPx = newRadius
        quality = newQuality
        symmetry = newSymmetry
        count = newCount
        radiusPx = newRadiusPx
        stateCode = newStateCode
        confidence = newConfidence

        if let c = newCenter {
            breadcrumb.append(c)
            if breadcrumb.count > breadcrumbCapacity {
                breadcrumb.removeFirst(breadcrumb.count - breadcrumbCapacity)
            }
        }

        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {
        let config = ballLockConfig

        guard config?.showBallLockDebug ?? true else { return }
        guard let centerBuf = roiCenterBuffer,
              let roiRadiusPx = roiRadiusPx,
              roiRadiusPx > 1 else {
            return
        }

        // Map center and radius from buffer space → view space
        let centerView = mapper.mapCGPoint(centerBuf)
        let edgeBuf = CGPoint(x: centerBuf.x + roiRadiusPx, y: centerBuf.y)
        let edgeView = mapper.mapCGPoint(edgeBuf)
        let radiusView = hypot(edgeView.x - centerView.x, edgeView.y - centerView.y)

        let roiRect = CGRect(
            x: centerView.x - radiusView,
            y: centerView.y - radiusView,
            width: radiusView * 2.0,
            height: radiusView * 2.0
        )

        // Base color by state
        let baseColor: UIColor
        switch stateCode {
        case 0:
            baseColor = UIColor(white: 0.7, alpha: 1.0) // searching
        case 1:
            baseColor = UIColor.yellow                 // candidate
        case 2:
            baseColor = UIColor.green                  // locked
        case 3:
            baseColor = UIColor.orange                 // cooldown
        default:
            baseColor = UIColor(white: 0.5, alpha: 1.0)
        }

        // ROI circle
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(baseColor.cgColor)
        ctx.strokeEllipse(in: roiRect)

        // Critical degeneracy (future) → red outline; for now approximate with low confidence.
        if confidence < 0.4 {
            let expandedRect = roiRect.insetBy(dx: -2.0, dy: -2.0)
            ctx.setLineWidth(3.0)
            ctx.setStrokeColor(UIColor.red.cgColor)
            ctx.strokeEllipse(in: expandedRect)
        }

        // Breadcrumb trail (buffer → view)
        if config?.showBallLockBreadcrumb ?? true, !breadcrumb.isEmpty {
            let n = breadcrumb.count
            for (idx, cBuf) in breadcrumb.enumerated() {
                let p = mapper.mapCGPoint(cBuf)
                let t = CGFloat(idx + 1) / CGFloat(n)
                let alpha = 0.15 + 0.35 * t
                ctx.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                let r: CGFloat = 2.0
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2.0, height: r * 2.0)
                ctx.fillEllipse(in: rect)
            }
        }

        // Centroid dot at ROI center
        let dotRadius: CGFloat = 3.0
        let dotRect = CGRect(
            x: centerView.x - dotRadius,
            y: centerView.y - dotRadius,
            width: dotRadius * 2.0,
            height: dotRadius * 2.0
        )
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: dotRect)

        // Optional cluster dots
        if config?.showClusterDots ?? true {
            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(UIColor.cyan.withAlphaComponent(0.7).cgColor)
            for pBuf in clusterDots {
                let p = mapper.mapCGPoint(pBuf)
                let r: CGFloat = 2.0
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2.0, height: r * 2.0)
                ctx.strokeEllipse(in: rect)
            }
        }

        // Text HUD near top-left of ROI
        if config?.showBallLockTextHUD ?? true {
            let stateText: String
            switch stateCode {
            case 0: stateText = "SEARCH"
            case 1: stateText = "CAND"
            case 2: stateText = "LOCKED"
            case 3: stateText = "COOLDN"
            default: stateText = "UNK"
            }

            let text = String(
                format: "STATE: %@\nQ: %.2f\nSYM: %.2f\nCNT: %d\nRAD: %.0fpx",
                stateText,
                quality,
                symmetry,
                count,
                radiusPx
            )

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]

            let textOriginX = max(4.0, roiRect.minX)
            let textOriginY = max(4.0, roiRect.minY - 70.0)
            let textRect = CGRect(
                x: textOriginX,
                y: textOriginY,
                width: 180.0,
                height: 70.0
            )

            UIGraphicsPushContext(ctx)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
            UIGraphicsPopContext()
        }
    }
}
