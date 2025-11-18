//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

// ------------------------------------------------------------
// MARK: - SwiftUI View
// ------------------------------------------------------------
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
    private let dotLayer = DotTrackingOverlayLayer()
    private let velocityLayer = VelocityOverlayLayer()
    private let poseLayer = PoseOverlayLayer()
    private let performanceHUD = PerformanceHUDLayer()

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
        performanceHUD.contentsScale = UIScreen.main.scale

        layer.addSublayer(dotLayer)
        layer.addSublayer(velocityLayer)
        layer.addSublayer(poseLayer)

        // 4th overlay (Model 1 pattern)
        layer.addSublayer(performanceHUD)
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
        performanceHUD.frame = bounds

        CATransaction.commit()
    }

    // ----------------------------------------------------------
    // MARK: - Redraw Trigger
    // ----------------------------------------------------------
    func updateOverlays() {
        guard let camera else { return }
        guard let frame = camera.latestFrame else { return }

        dotLayer.update(frame: frame)
        velocityLayer.update(frame: frame)
        poseLayer.update(frame: frame)
        performanceHUD.update(with: frame)
    }
}@EnvironmentObject private var camera: CameraManager

    private let performanceHUD = PerformanceHUDLayer()

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)

        // -- Attach as 4th overlay (Model 1 pattern) --
        performanceHUD.frame = view.bounds
        performanceHUD.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer.addSublayer(performanceHUD)
=======

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer.frame = bounds
        dotLayer.frame = bounds
        velocityLayer.frame = bounds
        poseLayer.frame = bounds
>>>>>>> origin/main

        CATransaction.commit()
    }

<<<<<<<+main
    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let frame = camera.latestFrame {
            performanceHUD.update(with: frame)
        }
=======
    // ----------------------------------------------------------
    // MARK: - Redraw Trigger
    // ----------------------------------------------------------
    func updateOverlays() {
        dotLayer.setNeedsDisplay()
        velocityLayer.setNeedsDisplay()
        poseLayer.setNeedsDisplay()
>>>>>>> origin/main
    }
}