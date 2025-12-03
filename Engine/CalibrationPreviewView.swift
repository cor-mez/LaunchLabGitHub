//
//  CalibrationPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

/// A minimal camera preview used during calibration.
/// Displays the live AVCaptureSession from CameraManager.
struct CalibrationPreviewView: UIViewRepresentable {

    @EnvironmentObject var camera: CameraManager

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PreviewView {
        // Use the new public CameraManager API
        let view = PreviewView(session: camera.captureSession)

        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoOrientation = .portrait

        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Keep preview session synchronized
        uiView.session = camera.captureSession
    }
}
