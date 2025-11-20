//
//  LaunchLabApp.swift
//  LaunchLab
//

import SwiftUI

@main
struct LaunchLabApp: App {

    @StateObject var camera = CameraManager()
    @StateObject var shot = ShotDetector.shared

    var body: some Scene {
        WindowGroup {
            NavigationView {
                VStack(spacing: 24) {

                    NavigationLink("LaunchLab Camera") {
                        RootView()
                            .environmentObject(camera)
                            .environmentObject(shot)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink("RS Timing Calibration") {
                        RSTimingCalibrationRootView()
                            .environmentObject(camera)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .padding()
                .navigationTitle("LaunchLab")
            }
        }
    }
}