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
    private let kltDebugLayer = KLTDebugOverlayLayer()
    private let poseLayer = PoseOverlayLayer()
    private let rsTimingLayer = RSTimingOverlayLayer()
    private let rsGeometryLayer = RSGeometryOverlayLayer()
    private let spinAxisLayer = SpinAxisOverlayLayer()
    private let rpeLayer = RPEOverlayLayer()
    private let performanceHUD = PerformanceHUDLayer()

    init(camera: CameraManager) {
        self.camera = camera
        super.init(frame: .zero)
        setupPreview()
        setupOverlays()
    }

    required init?(coder: NSCoder) { fatalError() }

    // --------------------------------------------------------
    // MARK: Preview Layer
    // --------------------------------------------------------
    private func setupPreview() {
        guard let camera else { return }
        previewLayer.session = camera.cameraSession
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    // --------------------------------------------------------
    // MARK: Overlay Layers Setup
    // --------------------------------------------------------
    private func setupOverlays() {

        dotLayer.contentsScale = UIScreen.main.scale
        velocityLayer.contentsScale = UIScreen.main.scale
        kltDebugLayer.contentsScale = UIScreen.main.scale
        poseLayer.contentsScale = UIScreen.main.scale
        rsTimingLayer.contentsScale = UIScreen.main.scale
        rsGeometryLayer.contentsScale = UIScreen.main.scale
        spinAxisLayer.contentsScale = UIScreen.main.scale
        rpeLayer.contentsScale = UIScreen.main.scale
        performanceHUD.contentsScale = UIScreen.main.scale

        // Z-ORDER (bottom → top)
        // 1. previewLayer
        // 2. dotLayer
        // 3. velocityLayer
        // 4. kltDebugLayer
        // 5. poseLayer
        // 6. rsTimingLayer
        // 7. rsGeometryLayer
        // 8. spinAxisLayer
        // 9. rpeLayer
        // 10. performanceHUD

        layer.addSublayer(dotLayer)
        layer.addSublayer(velocityLayer)
        layer.addSublayer(kltDebugLayer)
        layer.addSublayer(poseLayer)
        layer.addSublayer(rsTimingLayer)
        layer.addSublayer(rsGeometryLayer)
        layer.addSublayer(spinAxisLayer)
        layer.addSublayer(rpeLayer)
        layer.addSublayer(performanceHUD)
    }

    // --------------------------------------------------------
    // MARK: Layout Synchronization
    // --------------------------------------------------------
    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let allBounds = bounds

        previewLayer.frame = allBounds
        dotLayer.frame = allBounds
        velocityLayer.frame = allBounds
        kltDebugLayer.frame = allBounds
        poseLayer.frame = allBounds
        rsTimingLayer.frame = allBounds
        rsGeometryLayer.frame = allBounds
        spinAxisLayer.frame = allBounds
        rpeLayer.frame = allBounds
        performanceHUD.frame = allBounds

        CATransaction.commit()
    }

    // --------------------------------------------------------
    // MARK: Overlay Update Loop
    // --------------------------------------------------------
    func updateOverlays() {
        guard let camera, let frame = camera.latestFrame else { return }

        dotLayer.update(frame: frame)
        velocityLayer.update(frame: frame)
        kltDebugLayer.update(frame: frame)
        poseLayer.update(frame: frame)
        rsTimingLayer.update(frame: frame)
        rsGeometryLayer.update(frame: frame)
        spinAxisLayer.update(frame: frame)
        rpeLayer.update(frame: frame)
        performanceHUD.update(frame: frame)
    }
}