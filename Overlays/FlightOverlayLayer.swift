//
//  FlightOverlayLayer.swift
//  LaunchLab
//

import UIKit
import simd
import CoreGraphics

// =======================================================================
// MARK: - Flight Path Debug Overlay (Top-Down + Side View)
// =======================================================================
//
// Draws two debug projections:
//
// 1. TOP–DOWN VIEW (X,Z plane)
//    • X = forward (downrange)
//    • Z = lateral left/right
//
// 2. SIDE VIEW (X,Y plane)
//    • X = forward (downrange)
//    • Y = vertical height
//
// Both use the same trajectory array from BallFlightResult.
// Zero allocations inside draw().
//

final class FlightOverlayLayer: CALayer {

    // ------------------------------------------------------------
    // MARK: Mapper + Frame Inputs
    // ------------------------------------------------------------
    public var mapper: VisionOverlaySupport?
    public var flight: BallFlightResult?

    // Cached geometry (screen)
    private var width: CGFloat = 0
    private var height: CGFloat = 0

    // ------------------------------------------------------------
    // MARK: Update
    // ------------------------------------------------------------
    func update(frame: VisionFrameData) {
        self.flight = frame.flight
        self.width = bounds.width
        self.height = bounds.height
        setNeedsDisplay()
    }

    // ------------------------------------------------------------
    // MARK: Draw
    // ------------------------------------------------------------
    override func draw(in ctx: CGContext) {
        guard let flight = flight else { return }
        guard flight.trajectory.count > 2 else { return }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setLineWidth(2.0)

        // Layout regions:
        //
        // ---------------------------
        // |        TOP DOWN         |  (upper 55%)
        // ---------------------------
        // |         SIDE            |  (lower 45%)
        // ---------------------------
        //
        let topH = height * 0.55
        let botH = height * 0.45

        drawTopDown(in: ctx,
                    rect: CGRect(x: 0, y: 0, width: width, height: topH),
                    flight: flight)

        drawSideView(in: ctx,
                     rect: CGRect(x: 0, y: topH, width: width, height: botH),
                     flight: flight)

        drawHUD(in: ctx, flight: flight)
    }

    // ===================================================================
    // MARK: - TOP DOWN (X–Z) Projection
    // ===================================================================
    private func drawTopDown(in ctx: CGContext, rect: CGRect, flight: BallFlightResult) {

        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setStrokeColor(UIColor.systemTeal.cgColor)

        let traj = flight.trajectory
        guard traj.count >= 2 else { return }

        // Determine bounds to scale properly
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude

        for p in traj {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minZ = min(minZ, p.z)
            maxZ = max(maxZ, p.z)
        }

        // Padding and normalization
        let padX: Float = (maxX - minX) * 0.05
        let padZ: Float = (maxZ - minZ) * 0.05

        let loX = minX - padX
        let hiX = maxX + padX
        let loZ = minZ - padZ
        let hiZ = maxZ + padZ

        let spanX = max(hiX - loX, 0.1)
        let spanZ = max(hiZ - loZ, 0.1)

        // Convert (x,z) -> screen
        func map(_ p: SIMD3<Float>) -> CGPoint {
            let nx = CGFloat((p.x - loX) / spanX)      // 0 → 1
            let nz = CGFloat((p.z - loZ) / spanZ)      // 0 → 1
            let px = rect.minX + nx * rect.width
            let py = rect.maxY - nz * rect.height      // invert vertical
            return CGPoint(x: px, y: py)
        }

        // Draw polyline
        ctx.setLineWidth(2.0)
        ctx.beginPath()

        let p0 = map(traj[0])
        ctx.move(to: p0)

        for i in 1..<traj.count {
            ctx.addLine(to: map(traj[i]))
        }

        ctx.strokePath()

        // Draw origin dot
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: p0.x - 3, y: p0.y - 3, width: 6, height: 6))
    }

    // ===================================================================
    // MARK: - SIDE VIEW (X–Y) Projection
    // ===================================================================
    private func drawSideView(in ctx: CGContext, rect: CGRect, flight: BallFlightResult) {

        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setStrokeColor(UIColor.systemPink.cgColor)

        let traj = flight.trajectory
        guard traj.count >= 2 else { return }

        // Bounds
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude

        for p in traj {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let padX: Float = (maxX - minX) * 0.05
        let padY: Float = (maxY - minY) * 0.10

        let loX = minX - padX
        let hiX = maxX + padX
        let loY = minY - padY
        let hiY = maxY + padY

        let spanX = max(hiX - loX, 0.1)
        let spanY = max(hiY - loY, 0.1)

        // (x,y) → screen
        func map(_ p: SIMD3<Float>) -> CGPoint {
            let nx = CGFloat((p.x - loX) / spanX)
            let ny = CGFloat((p.y - loY) / spanY)
            let px = rect.minX + nx * rect.width
            let py = rect.maxY - ny * rect.height   // invert vertical
            return CGPoint(x: px, y: py)
        }

        // Polyline
        ctx.setLineWidth(2.0)
        ctx.beginPath()

        let p0 = map(traj[0])
        ctx.move(to: p0)

        for i in 1..<traj.count {
            ctx.addLine(to: map(traj[i]))
        }

        ctx.strokePath()

        // Draw landing marker
        let pEnd = map(traj.last!)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: pEnd.x - 3, y: pEnd.y - 3, width: 6, height: 6))
    }

    // ===================================================================
    // MARK: - HUD (Top-left text box)
    // ===================================================================
    private func drawHUD(in ctx: CGContext, flight: BallFlightResult) {

        let text = String(
            format:
            "Carry: %.1f m\nApex: %.1f m\nSide: %.2f m\nAngle: %.1f°",
            flight.carryDistance,
            flight.apexHeight,
            flight.sideCurve,
            flight.landingAngle * 180.0 / .pi
        )

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.white
        ]

        let box = CGRect(x: 8, y: 8, width: 160, height: 70)
        text.draw(in: box, withAttributes: attrs)
    }
}