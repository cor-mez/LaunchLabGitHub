//
//  LaunchLabApp.swift
//

import SwiftUI

@main
struct LaunchLabApp: App {

    @StateObject var camera = CameraManager.shared
    @StateObject var shot = ShotDetector.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)
                .environmentObject(shot)
        }
    }
}
