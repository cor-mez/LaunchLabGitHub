//
//  RSTimingCalibrationView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

struct RSTimingCalibrationView: View {

    @ObservedObject var controller: RSTimingCalibrationController

    var body: some View {
        VStack(spacing: 16) {

            HStack(spacing: 16) {
                Button(action: controller.start) {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: controller.stop) {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button("Fit Model") {
                controller.fitModel(height: 1080)
            }
            .buttonStyle(.bordered)

            Button("Save Model") {
                controller.saveModel()
            }
            .buttonStyle(.bordered)

            Button("Load Model") {
                controller.loadModel()
            }
            .buttonStyle(.bordered)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Samples: \(controller.samples.count)")
                    Text("Curve points: \(controller.curve.count)")
                    Text(String(format: "Readout: %.4f s", controller.readout))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .padding()
    }
}