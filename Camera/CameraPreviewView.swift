//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

final class PreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    @EnvironmentObject private var camera: CameraManager

    private let performanceHUD = PerformanceHUDLayer()

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)

        // -- Attach as 4th overlay (Model 1 pattern) --
        performanceHUD.frame = view.bounds
        performanceHUD.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer.addSublayer(performanceHUD)

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let frame = camera.latestFrame {
            performanceHUD.update(with: frame)
        }
    }
}