//
//  CalibrationPreviewContainer.swift
//  LaunchLab
//

import SwiftUI

struct CalibrationPreviewContainer: View {

    @EnvironmentObject var camera: CameraManager

    var body: some View {
        ZStack {
            CalibrationPreviewView()
                .environmentObject(camera)

            VStack {
                Text("Calibration Mode")
                    .font(.headline)
                    .padding(.top, 20)
                Spacer()
            }
        }
    }
}
