// File: Engine/CalibrationPreviewView.swift
//
//  CalibrationPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

struct CalibrationPreviewView: UIViewRepresentable {

    @EnvironmentObject var camera: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: camera.session)
        view.videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = camera.session
    }
}
