//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    let intrinsics: CameraIntrinsics

    @EnvironmentObject private var camera: CameraManager

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // ============================================================
    // MARK: - MAKE UI VIEW
    // ============================================================
    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()

        // Preview
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        // --------------------------------------------------------
        // Create overlays
        // --------------------------------------------------------
        let dotLayer        = DotTrackingOverlayLayer()
        let velocityLayer   = VelocityOverlayLayer()
        let rsLineLayer     = RSLineIndexOverlayLayer()
        let rspnpLayer      = RSPnPDebugOverlayLayer()
        let spinAxisLayer   = SpinAxisOverlayLayer()
        let spinDriftLayer  = SpinDriftOverlayLayer()
        let rpeLayer        = RPEOverlayLayer()
        let hudLayer        = HUDOverlayLayer()

        view.dotLayer       = dotLayer
        view.velocityLayer  = velocityLayer
        view.rsLineLayer    = rsLineLayer
        view.rspnpLayer     = rspnpLayer
        view.spinAxisLayer  = spinAxisLayer
        view.spinDriftLayer = spinDriftLayer
        view.rpeLayer       = rpeLayer
        view.hudLayer       = hudLayer

        // --------------------------------------------------------
        // Add in correct z-order (bottom → top)
        // --------------------------------------------------------
        view.layer.addSublayer(dotLayer)
        view.layer.addSublayer(velocityLayer)
        view.layer.addSublayer(rsLineLayer)
        view.layer.addSublayer(rspnpLayer)
        view.layer.addSublayer(spinAxisLayer)
        view.layer.addSublayer(spinDriftLayer)   // NEW layer
        view.layer.addSublayer(rpeLayer)
        view.layer.addSublayer(hudLayer)

        return view
    }

    // ============================================================
    // MARK: - UPDATE UI VIEW
    // ============================================================
    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        guard let frame = camera.latestFrame else { return }

        uiView.previewLayer?.frame = uiView.bounds
        uiView.intrinsics = intrinsics

        uiView.updateFrame(frame, size: uiView.bounds.size)
    }

    class Coordinator: NSObject {
        let parent: CameraPreviewView
        init(_ parent: CameraPreviewView) { self.parent = parent }
    }
}