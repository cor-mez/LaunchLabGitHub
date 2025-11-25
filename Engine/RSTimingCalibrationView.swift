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

            // ----------------------------------------------------
            // MARK: Start / Stop Row
            // ----------------------------------------------------
            HStack(spacing: 16) {

                // START
                Button("Start") {
                    controller.start()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)

                // STOP
                Button("Stop") {
                    controller.stop()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }

            // ----------------------------------------------------
            // MARK: Fit / Save / Load
            // ----------------------------------------------------
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

            // ----------------------------------------------------
            // MARK: Diagnostic Output
            // ----------------------------------------------------
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Samples: \(controller.sampleCount)")
                    Text(String(format: "Readout: %.4f s", controller.estimatedReadout))
                    Text(String(format: "Linearity: %.3f", controller.estimatedLinearity))
                    Text("Completed: \(controller.isComplete ? "Yes" : "No")")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .padding()
    }
}
