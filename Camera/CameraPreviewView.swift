//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {

    @EnvironmentObject var camera: CameraManager

    func makeUIView(context: Context) -> CameraPreviewContainer {
        CameraPreviewContainer(camera: camera)
    }

    func updateUIView(_ uiView: CameraPreviewContainer, context: Context) {
        uiView.updateOverlays()
    }
}

// ============================================================
// MARK: - UIKit Container
// ============================================================

final class CameraPreviewContainer: UIView {

    private weak var camera: CameraManager?

    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let dotLayer = DotTrackingOverlayLayer()
    private let velocityLayer = VelocityOverlayLayer()
    private let poseLayer = PoseOverlayLayer()
    private let spinAxisLayer = SpinAxisOverlayLayer()
    private let performanceHUD = PerformanceHUDLayer()

    init(camera: CameraManager) {
        self.camera = camera
        super.init(frame: .zero)
        setupPreview()
        setupOverlays()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupPreview() {
        guard let camera else { return }
        previewLayer.session = camera.cameraSession
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    private func setupOverlays() {
        dotLayer.contentsScale = UIScreen.main.scale
        velocityLayer.contentsScale = UIScreen.main.scale
        poseLayer.contentsScale = UIScreen.main.scale
        spinAxisLayer.contentsScale = UIScreen.main.scale
        performanceHUD.contentsScale = UIScreen.main.scale

        layer.addSublayer(dotLayer)
        layer.addSublayer(velocityLayer)
        layer.addSublayer(poseLayer)
        layer.addSublayer(spinAxisLayer)
        layer.addSublayer(performanceHUD)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer.frame = bounds
        dotLayer.frame = bounds
        velocityLayer.frame = bounds
        poseLayer.frame = bounds
        spinAxisLayer.frame = bounds
        performanceHUD.frame = bounds

        CATransaction.commit()
    }

    func updateOverlays() {
        guard let camera, let frame = camera.latestFrame else { return }

        dotLayer.update(frame: frame)
        velocityLayer.update(frame: frame)
        poseLayer.update(frame: frame)
        spinAxisLayer.update(frame: frame)
        performanceHUD.update(with: frame)
    }
}