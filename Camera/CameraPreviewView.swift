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
        let container = CameraPreviewContainer(camera: camera)
        return container
    }

    func updateUIView(_ uiView: CameraPreviewContainer, context: Context) {
        uiView.updateOverlays()
    }
}


// ============================================================
// MARK: - UIKit Container View
// ============================================================

final class CameraPreviewContainer: UIView {

    // MARK: - External Owner
    private weak var camera: CameraManager?

    // MARK: - Layers
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let dotLayer = DotOverlayLayer()
    private let velocityLayer = VelocityOverlayLayer()
    private let poseLayer = PoseOverlayLayer()

    // MARK: - Init
    init(camera: CameraManager) {
        self.camera = camera
        super.init(frame: .zero)

        setupPreview()
        setupOverlays()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // ----------------------------------------------------------
    // MARK: - Setup Preview Layer
    // ----------------------------------------------------------
    private func setupPreview() {
        guard let camera else { return }

        previewLayer.session = camera.cameraSession
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    // ----------------------------------------------------------
    // MARK: - Setup Overlay Layers
    // ----------------------------------------------------------
    private func setupOverlays() {
        dotLayer.camera = camera
        velocityLayer.camera = camera
        poseLayer.camera = camera

        dotLayer.contentsScale = UIScreen.main.scale
        velocityLayer.contentsScale = UIScreen.main.scale
        poseLayer.contentsScale = UIScreen.main.scale

        layer.addSublayer(dotLayer)
        layer.addSublayer(velocityLayer)
        layer.addSublayer(poseLayer)
    }

    // ----------------------------------------------------------
    // MARK: - Layout
    // ----------------------------------------------------------
    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer.frame = bounds
        dotLayer.frame = bounds
        velocityLayer.frame = bounds
        poseLayer.frame = bounds

        CATransaction.commit()
    }

    // ----------------------------------------------------------
    // MARK: - Redraw Trigger
    // ----------------------------------------------------------
    func updateOverlays() {
        dotLayer.setNeedsDisplay()
        velocityLayer.setNeedsDisplay()
        poseLayer.setNeedsDisplay()
    }
}
