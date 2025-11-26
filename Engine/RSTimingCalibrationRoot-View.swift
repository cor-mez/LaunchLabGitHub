//
//  RSTimingCalibrationRoot-View.swift
//  LaunchLab
//

import SwiftUI

struct RSTimingCalibrationRootView: View {

    @EnvironmentObject var camera: CameraManager

    var body: some View {
        VStack {
            Text("RS Timing Calibration")
                .font(.title2)
                .padding()

            CalibrationPreviewView()
                .environmentObject(camera)

            Spacer()
        }
    }
}
