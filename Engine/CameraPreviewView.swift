//
//  CameraPreviewView.swift
//  LaunchLab
//

import UIKit
import AVFoundation

final class CameraPreviewView: UIView {

    // Use AVCaptureVideoPreviewLayer as backing layer
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private var overlays: [BaseOverlayLayer] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        safeConfigure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        safeConfigure()
    }

    // MARK: - Main-thread-safe configuration

    private func safeConfigure() {
        // Ensure ALL UIKit operations run on main
        DispatchQueue.main.async {
            self.backgroundColor = .black
            self.previewLayer.videoGravity = .resizeAspectFill
        }
    }

    // MARK: - Session Attach

    func attachSession(_ session: AVCaptureSession) {
        DispatchQueue.main.async {
            self.previewLayer.session = session
        }
    }

    // MARK: - Overlays

    func addOverlay(_ layer: BaseOverlayLayer) {
        DispatchQueue.main.async {
            layer.frame = self.bounds
            self.overlays.append(layer)
            self.layer.addSublayer(layer)
            layer.setNeedsDisplay()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Ensure overlay frames update on main thread
        if Thread.isMainThread {
            for o in overlays {
                o.frame = bounds
                o.setNeedsDisplay()
            }
        } else {
            DispatchQueue.main.async {
                for o in self.overlays {
                    o.frame = self.bounds
                    o.setNeedsDisplay()
                }
            }
        }
    }
}
