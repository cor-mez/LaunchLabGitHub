//
//  ProModeDebugSuiteLayer.swift
//  LaunchLab
//
//  Pro Mode DEBUG OVERLAY (V1)
//
//  ROLE (STRICT):
//  - Visualize observational Engine outputs
//  - Debug rendering ONLY
//  - NO authority
//  - NO cadence inference
//  - NO acceptance semantics
//

import UIKit
import simd

final class ProModeDebugSuiteLayer: BaseOverlayLayer {

    // -----------------------------------------------------------
    // MARK: - Frame Storage (OBSERVATIONAL)
    // -----------------------------------------------------------

    private var frameData: VisionFrameData?

    // Visual-only profiler history (NOT cadence)
    private var timingHistory: [Float] = []
    private let timingMax = 120

    // Debug logging buffer (non-authoritative)
    private var logBuffer: [String] = []
    private let maxLogLines = 2000

    // Explicit debug toggle
    public var debugMode: Bool = false {
        didSet { setNeedsDisplay() }
    }

    // -----------------------------------------------------------
    // MARK: - Update API
    // -----------------------------------------------------------

    /// Update overlay with the latest observational frame.
    /// All values here are for visualization only.
    func updateWithFrame(
        _ frame: VisionFrameData,
        profilerTime: Float,
        debugFlag: Bool
    ) {
        self.frameData = frame
        self.debugMode = debugFlag

        timingHistory.append(profilerTime)
        if timingHistory.count > timingMax {
            timingHistory.removeFirst()
        }

        if debugMode {
            appendLog(frame)
        }

        setNeedsDisplay()
    }

    // -----------------------------------------------------------
    // MARK: - TEMP ADAPTERS (DEBUG ONLY)
    // -----------------------------------------------------------

    struct RSBearing {
        let rowIndex: Float
    }

    struct RSCorrectedPoint {
        let corrected: CGPoint
    }

    // -----------------------------------------------------------
    // MARK: - Draw
    // -----------------------------------------------------------

    /// NOTE:
    /// This is NOT an override.
    /// BaseOverlayLayer does not declare drawOverlay(_:mapper:).
    func drawOverlay(in ctx: CGContext, mapper: OverlayMapper) {

        guard debugMode else { return }
        guard let frame = frameData else { return }

        drawTextPanel(ctx, frame: frame)
        drawDotGrid(ctx, frame: frame)

        if let flow = frame.flowVectors {
            drawFlowVectors(ctx, flow: flow)
        }

        // RS timing visualization (debug only)
        if let b = frame.bearings {
            let wrapped = b.map { RSBearing(rowIndex: $0) }
            drawRSTiming(ctx, bearings: wrapped)
        }

        // Residual rays (debug only)
        if let r = frame.residuals,
           let c = frame.correctedPoints {
            let wrapped = c.map { RSCorrectedPoint(corrected: $0) }
            drawRPERays(ctx, residuals: r, corrected: wrapped)
        }

        // Spin axis (debug only, NON-AUTHORITATIVE)
        if let spin = frame.spin {
            drawSpinAxis(ctx, spin: spin)
        }

        drawProfilerChart(ctx)
    }

    // -----------------------------------------------------------
    // MARK: - Drawing helpers
    // -----------------------------------------------------------

    private func drawTextPanel(_ ctx: CGContext, frame: VisionFrameData) {

        var lines: [String] = ["DEBUG VIEW — NON-AUTHORITATIVE"]

        if let rs = frame.rspnp {
            lines.append("RSPnP valid=\(rs.isValid ? 1 : 0)")
            lines.append(String(format:"t=(%.2f,%.2f,%.2f)", rs.t.x, rs.t.y, rs.t.z))
            lines.append(String(format:"v=(%.2f,%.2f,%.2f)", rs.v.x, rs.v.y, rs.v.z))
            lines.append(String(format:"w=(%.2f,%.2f,%.2f)", rs.w.x, rs.w.y, rs.w.z))
            lines.append(String(format:"resid=%.4f", rs.residual))
        }

        if let spin = frame.spin {
            lines.append(String(format:"Spin (debug)=%.0f RPM", spin.rpm))
            lines.append(
                String(
                    format:"Axis=(%.2f,%.2f,%.2f)",
                    spin.axis.x, spin.axis.y, spin.axis.z
                )
            )
        }

        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key:Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        var y: CGFloat = 8
        for l in lines {
            l.draw(at: CGPoint(x: 8, y: y), withAttributes: attrs)
            y += 16
        }
    }

    private func drawDotGrid(_ ctx: CGContext, frame: VisionFrameData) {

        ctx.setStrokeColor(UIColor.white.cgColor)

        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .light)
        let attrs: [NSAttributedString.Key:Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        for d in frame.dots {
            let p = d.position
            let r = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
            ctx.stroke(r)

            "\(d.id)".draw(
                at: CGPoint(x: p.x + 6, y: p.y - 6),
                withAttributes: attrs
            )
        }
    }

    private func drawFlowVectors(_ ctx: CGContext, flow: [SIMD2<Float>]) {

        ctx.setLineWidth(1)
        ctx.setStrokeColor(UIColor.green.cgColor)

        for v in flow {
            let p = CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
            let q = CGPoint(
                x: p.x + CGFloat(v.x * 5),
                y: p.y + CGFloat(v.y * 5)
            )
            ctx.beginPath()
            ctx.move(to: p)
            ctx.addLine(to: q)
            ctx.strokePath()
        }
    }

    private func drawRSTiming(_ ctx: CGContext, bearings: [RSBearing]) {

        ctx.setLineWidth(0.5)
        ctx.setStrokeColor(
            UIColor.blue.withAlphaComponent(0.5).cgColor
        )

        for b in bearings {
            let y = CGFloat(b.rowIndex)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            ctx.strokePath()
        }
    }

    private func drawRPERays(
        _ ctx: CGContext,
        residuals: [RPEResidual],
        corrected: [RSCorrectedPoint]
    ) {

        ctx.setLineWidth(1)
        ctx.setStrokeColor(
            UIColor.red.withAlphaComponent(0.6).cgColor
        )

        for (i, r) in residuals.enumerated() where i < corrected.count {
            let c = corrected[i].corrected
            let end = CGPoint(
                x: c.x + CGFloat(r.error.x),
                y: c.y + CGFloat(r.error.y)
            )

            ctx.beginPath()
            ctx.move(to: c)
            ctx.addLine(to: end)
            ctx.strokePath()
        }
    }

    private func drawSpinAxis(_ ctx: CGContext, spin: SpinResult) {

        let L: CGFloat = 40
        let a = spin.axis

        let p0 = CGPoint(x: bounds.midX, y: bounds.midY)
        let p1 = CGPoint(
            x: p0.x + CGFloat(a.x) * L,
            y: p0.y - CGFloat(a.y) * L
        )

        ctx.setLineWidth(2)
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        ctx.beginPath()
        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.strokePath()
    }

    private func drawProfilerChart(_ ctx: CGContext) {

        guard !timingHistory.isEmpty else { return }

        let W: CGFloat = 120
        let H: CGFloat = 60
        let x0 = bounds.width - W - 10
        let y0 = bounds.height - H - 10

        ctx.setFillColor(
            UIColor(white:0.1, alpha:0.5).cgColor
        )
        ctx.fill(CGRect(x: x0, y: y0, width: W, height: H))

        let maxVal = CGFloat(timingHistory.max() ?? 1)

        ctx.setFillColor(UIColor.green.cgColor)

        for (i, t) in timingHistory.enumerated() {
            let h = H * CGFloat(t) / maxVal
            let x = x0 + CGFloat(i) * (W / CGFloat(timingHistory.count))
            let y = y0 + (H - h)
            ctx.fill(
                CGRect(x: x, y: y, width: 2, height: h)
            )
        }
    }

    // -----------------------------------------------------------
    // MARK: - Debug Logging (NON-AUTHORITATIVE)
    // -----------------------------------------------------------

    private func appendLog(_ f: VisionFrameData) {

        var s = String(format: "t=%.3f", f.timestamp)

        if let r = f.rspnp {
            s += String(format:" RSPnP(resid=%.3f)", r.residual)
        }

        logBuffer.append(s)
        if logBuffer.count > maxLogLines {
            logBuffer.removeFirst()
        }
    }

    public func exportLog() -> String {
        debugMode ? logBuffer.joined(separator: "\n") : ""
    }
}
