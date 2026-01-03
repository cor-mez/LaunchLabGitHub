//
//  PostImpactROICatcher.swift
//  LaunchLab
//
//  Geometry-Seeded ROI-B v2 (LOG-VERIFIED)
//
//  Purpose:
//  • Reacquire ball immediately after impact
//  • Geometry-first direction, refined by motion
//  • LOGS guarantee ROI-B lifecycle observability
//

import CoreGraphics

final class PostImpactROICatcher {

    // MARK: - Parameters

    private let maxFrames: Int = 5
    private let roiLength: CGFloat = 460
    private let roiWidth: CGFloat = 160
    private let stepPerFrame: CGFloat = 90

    // MARK: - State

    private var origin: CGPoint?
    private var direction: CGVector?
    private var frameIndex: Int = 0
    private(set) var isActive: Bool = false
    private var usingFallback: Bool = false

    // MARK: - Lifecycle

    func reset() {
        origin = nil
        direction = nil
        frameIndex = 0
        isActive = false
        usingFallback = false
    }

    /// Arm ROI-B with guaranteed direction.
    func arm(at impactCenter: CGPoint, imageSize: CGSize) {
        origin = impactCenter
        frameIndex = 0
        isActive = true

        // Geometry-seeded fallback
        let imageCenter = CGPoint(
            x: imageSize.width * 0.5,
            y: imageSize.height * 0.5
        )

        var dx = impactCenter.x - imageCenter.x
        var dy = impactCenter.y - imageCenter.y

        // Bias upward
        if dy > 0 { dy = -abs(dy) }

        let mag = hypot(dx, dy)
        if mag > 1e-6 {
            let dir = CGVector(dx: dx / mag, dy: dy / mag)
            direction = dir
            usingFallback = true

            Log.info(
                .shot,
                "[ROI-B] armed fallback dir=(\(fmt(dir.dx)),\(fmt(dir.dy)))"
            )
        } else {
            direction = CGVector(dx: 0, dy: -1)
            usingFallback = true
            Log.info(.shot, "[ROI-B] armed default vertical fallback")
        }
    }

    /// Refine direction from motion if available.
    func updateDirection(_ v: CGVector) {
        let mag = hypot(v.dx, v.dy)
        guard mag > 1e-6 else { return }

        let dir = CGVector(dx: v.dx / mag, dy: v.dy / mag)
        direction = dir
        usingFallback = false

        Log.info(
            .shot,
            "[ROI-B] direction refined from motion (\(fmt(dir.dx)),\(fmt(dir.dy)))"
        )
    }

    /// Generate ROI-B for this frame.
    func makeROI(fullSize: CGSize) -> CGRect? {
        guard isActive,
              let origin,
              let dir = direction,
              frameIndex < maxFrames
        else {
            Log.info(.shot, "[ROI-B] expired or invalid — reset")
            reset()
            return nil
        }

        let offset = CGFloat(frameIndex + 1) * stepPerFrame
        let cx = origin.x + dir.dx * offset
        let cy = origin.y + dir.dy * offset

        let rect = CGRect(
            x: cx - roiLength * 0.5,
            y: cy - roiWidth * 0.5,
            width: roiLength,
            height: roiWidth
        ).intersection(CGRect(origin: .zero, size: fullSize))

        Log.info(
            .shot,
            "[ROI-B] frame=\(frameIndex) center=(\(fmt(cx)),\(fmt(cy))) mode=\(usingFallback ? "fallback" : "motion")"
        )

        return rect
    }

    func consumeFrame() {
        frameIndex += 1
        if frameIndex >= maxFrames {
            Log.info(.shot, "[ROI-B] max frames reached — reset")
            reset()
        }
    }

    // MARK: - Helpers

    private func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", v)
    }
}
