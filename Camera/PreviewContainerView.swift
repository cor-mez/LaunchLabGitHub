//
//  PreviewContainerView.swift
//  LaunchLab
//

import UIKit
import AVFoundation
import simd

final class PreviewContainerView: UIView {

    // ============================================================
    // MARK: - Layers
    // ============================================================
    var previewLayer: AVCaptureVideoPreviewLayer?

    var dotLayer: DotTrackingOverlayLayer?
    var velocityLayer: VelocityOverlayLayer?
    var rsLineLayer: RSLineIndexOverlayLayer?
    var rspnpLayer: RSPnPDebugOverlayLayer?
    var spinAxisLayer: SpinAxisOverlayLayer?
    var spinDriftLayer: SpinDriftOverlayLayer?
    var rpeLayer: RPEOverlayLayer?
    var hudLayer: HUDOverlayLayer?

    // Intrinsics for mapper
    var intrinsics: CameraIntrinsics = .zero

    // The LAST frame (needed for prevSpin)
    private var previousFrame: VisionFrameData?

    // ============================================================
    // MARK: - FRAME UPDATE
    // ============================================================
    func updateFrame(_ frame: VisionFrameData, size: CGSize) {

        guard let previewLayer else { return }

        // Build mapper
        let mapper = VisionOverlaySupport(
            bufferWidth: frame.width,
            bufferHeight: frame.height,
            viewSize: size,
            previewLayer: previewLayer
        )

        // --------------------------------------------------------
        // DOTS
        // --------------------------------------------------------
        if let L = dotLayer {
            L.frame = bounds
            L.mapper = mapper
            L.dots = frame.dots
        }

        // --------------------------------------------------------
        // VELOCITY
        // --------------------------------------------------------
        if let L = velocityLayer {
            L.frame = bounds
            L.mapper = mapper
            L.dots = frame.dots
        }

        // --------------------------------------------------------
        // RS LINE
        // --------------------------------------------------------
        if let L = rsLineLayer {
            L.frame = bounds
            L.mapper = mapper
            L.rsIndex = frame.rsLineIndex
        }

        // --------------------------------------------------------
        // RS-PnP DEBUG
        // --------------------------------------------------------
        if let L = rspnpLayer {
            L.frame = bounds
            L.mapper = mapper
            L.corrected = frame.rsCorrected
        }

        // --------------------------------------------------------
        // SPIN AXIS OVERLAY
        // --------------------------------------------------------
        if let L = spinAxisLayer {
            L.frame = bounds
            L.mapper = mapper
            L.spin = frame.spin
        }

        // --------------------------------------------------------
        // SPIN DRIFT OVERLAY (NEW)
        // --------------------------------------------------------
        if let L = spinDriftLayer {
            L.frame = bounds
            L.mapper = mapper

            L.spin       = frame.spin
            L.spinDrift  = frame.spinDrift
            L.prevSpin   = previousFrame?.spin   // <-- Correct fix

            // Updates cached drawing state
            L.updateFrame(frame, size: size)
        }

        // --------------------------------------------------------
        // RPE
        // --------------------------------------------------------
        if let L = rpeLayer {
            L.frame = bounds
            L.mapper = mapper
            L.residuals = frame.rsResiduals
        }

        // --------------------------------------------------------
        // HUD
        // --------------------------------------------------------
        if let L = hudLayer {
            L.frame = bounds
            L.latestFrame = frame
        }

        // Trigger draw
        layer.setNeedsDisplay()
        sublayers?.forEach { $0.setNeedsDisplay() }

        // Store for next frame (needed for prevSpin)
        previousFrame = frame
    }
}