//
//  CalibrationProgressOverlay.swift
//  LaunchLab
//

import UIKit
import CoreGraphics

/// Draws visual progress + status indicators during Auto-Calibration v1.
/// This overlay is passive -- it only renders what CalibrationFlowView feeds it.
/// No allocations occur in draw(). Everything is pre-cached.
final class CalibrationProgressOverlay: CALayer {

    // ============================================================
    // MARK: - Public Properties (set externally)
    // ============================================================
    public var phase: Phase = .idle      { didSet { setNeedsDisplay() } }
    public var progress: CGFloat = 0.0   { didSet { setNeedsDisplay() } }

    // Message strings (cached)
    public var title: String = "Calibration" {
        didSet { setNeedsDisplay() }
    }
    public var subtitle: String = "" {
        didSet { setNeedsDisplay() }
    }

    // ============================================================
    // MARK: - Phase Enum
    // ============================================================
    public enum Phase {
        case idle
        case collecting
        case processing
        case complete
    }

    // ============================================================
    // MARK: - Drawing
    // ============================================================
    override func draw(in ctx: CGContext) {

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // Semi-transparent dark background
        ctx.setFillColor(UIColor(white: 0.0, alpha: 0.2).cgColor)
        ctx.fill(bounds)

        drawTitle(in: ctx)
        drawBar(in: ctx)
        drawSubtitle(in: ctx)
    }

    // ============================================================
    // MARK: - Title Rendering
    // ============================================================
    private func drawTitle(in ctx: CGContext) {

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.white
        ]

        let box = CGRect(
            x: 16,
            y: bounds.height * 0.10,
            width: bounds.width - 32,
            height: 30
        )

        title.draw(in: box, withAttributes: attrs)
    }

    // ============================================================
    // MARK: - Subtitle Rendering
    // ============================================================
    private func drawSubtitle(in ctx: CGContext) {

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor(white: 1.0, alpha: 0.85)
        ]

        let box = CGRect(
            x: 16,
            y: bounds.height * 0.16,
            width: bounds.width - 32,
            height: 50
        )

        subtitle.draw(in: box, withAttributes: attrs)
    }

    // ============================================================
    // MARK: - Progress Bar
    // ============================================================
    private func drawBar(in ctx: CGContext) {

        let barWidth = bounds.width * 0.70
        let barHeight: CGFloat = 12

        let x = (bounds.width - barWidth) / 2
        let y = bounds.height * 0.30

        // Background
        let bgRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
        ctx.setFillColor(UIColor(white: 1.0, alpha: 0.15).cgColor)
        ctx.fill(bgRect)

        // Progress
        let w = max(0, min(progress, 1.0)) * barWidth
        if w > 0 {
            let fgRect = CGRect(x: x, y: y, width: w, height: barHeight)
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            ctx.fill(fgRect)
        }
    }
}