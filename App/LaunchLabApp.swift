//
//  LaunchLabApp.swift
//

import SwiftUI

@main
struct LaunchLabApp: App {

    @StateObject var camera = CameraManager()        // ❌ was CameraManager.shared
    @StateObject var shot = ShotDetector.shared      // keep this if ShotDetector IS a singleton

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)
                .environmentObject(shot)
        }
    }
}
