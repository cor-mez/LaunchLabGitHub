//
//  CalibrationPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

struct CalibrationPreviewView: UIViewRepresentable {

    @ObservedObject var controller: RSTimingCalibrationController
    @EnvironmentObject var camera: CameraManager

    func makeUIView(context: Context) -> CalibrationPreviewContainer {
        CalibrationPreviewContainer(controller: controller, camera: camera)
    }

    func updateUIView(_ uiView: CalibrationPreviewContainer, context: Context) {
        uiView.updateOverlay()
    }
}