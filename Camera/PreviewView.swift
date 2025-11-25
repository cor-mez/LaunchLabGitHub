//
//  PreviewView.swift
//  LaunchLab
//

import UIKit
import AVFoundation

/// Hosts the AVCaptureVideoPreviewLayer and all overlay CALayers.
/// Overlays are added directly as sublayers on top of the preview layer.
final class PreviewView: UIView {

    // MARK: - Session
    var session: AVCaptureSession {
        didSet { videoPreviewLayer.session = session }
    }

    // MARK: - Preview Layer
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    // MARK: - Overlay Layers
    private var overlayLayers: [BaseOverlayLayer] = []

    // MARK: - Init
    init(session: AVCaptureSession) {
        self.session = session
        super.init(frame: .zero)
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        self.session = AVCaptureSession()
        super.init(coder: coder)
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: - Overlay API
    func installOverlayLayers(_ layers: [BaseOverlayLayer]) {
        // Remove old
        for l in overlayLayers { l.removeFromSuperlayer() }
        overlayLayers = layers

        // Add new
        for l in layers {
            layer.addSublayer(l)
        }

        setNeedsLayout()
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()

        videoPreviewLayer.frame = bounds

        // Resize overlays
        for l in overlayLayers {
            l.frame = bounds
            l.setNeedsDisplay()
        }
    }
}
