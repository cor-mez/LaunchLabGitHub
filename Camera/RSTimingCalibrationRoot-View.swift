//
//  RSTimingCalibrationRootView.swift
//  LaunchLab
//

import SwiftUI

struct RSTimingCalibrationRootView: View {

    @EnvironmentObject var camera: CameraManager
    @StateObject private var controller = RSTimingCalibrationController()

    var body: some View {
        VStack(spacing: 0) {

            CalibrationPreviewView(controller: controller)
                .environmentObject(camera)
                .frame(maxHeight: 360)

            Divider()

            RSTimingCalibrationView(controller: controller)
                .padding(.top, 12)
        }
        .navigationBarTitle("RS Timing Calibration", displayMode: .inline)
        .onAppear {
            camera.enableCalibrationMode(controller)
        }
        .onDisappear {
            camera.disableCalibrationMode()
        }
    }
}