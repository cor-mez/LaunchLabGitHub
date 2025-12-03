//
//  CameraPreviewView.swift
//  LaunchLab
//

import UIKit
import AVFoundation

final class CameraPreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private var overlays: [BaseOverlayLayer] = []

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