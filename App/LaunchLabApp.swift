//  LaunchLabApp.swift
//  LaunchLab
//

import SwiftUI

@main
struct LaunchLabApp: App {

    @StateObject private var camera = CameraManager()
    @StateObject private var config = OverlayConfig()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)                    // CameraManager
                .environmentObject(config)                    // OverlayConfig
                .environmentObject(camera.ballLockConfig)     // BallLockConfig
        }
    }
}
