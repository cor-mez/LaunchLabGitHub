//
//  CalibrationPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

struct CalibrationPreviewView: UIViewRepresentable {

    @EnvironmentObject var camera: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: camera.cameraSession)
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = camera.cameraSession
    }
}
