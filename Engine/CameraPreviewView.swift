//
//  CameraPreviewView.swift
//  LaunchLab
//

import UIKit
import AVFoundation

/// The core camera rendering view.
/// Displays the live camera feed using AVCaptureVideoPreviewLayer.
/// Supports overlay layers (dots, ROI, RS residuals, spin, debug).
final class CameraPreviewView: UIView {

    // MARK: - Preview Layer

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    // MARK: - Overlay Layers

    private var overlays: [BaseOverlayLayer] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: - Attach

    func attachSession(_ session: AVCaptureSession) {
        previewLayer.session = session
    }

    func addOverlay(_ layer: BaseOverlayLayer) {
        layer.frame = bounds
        overlays.append(layer)
        self.layer.addSublayer(layer)
        layer.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for o in overlays {
            o.frame = bounds
            o.setNeedsDisplay()
        }
    }
}
