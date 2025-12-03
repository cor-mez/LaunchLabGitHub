//
//  RootView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

struct RootView: View {

    @EnvironmentObject private var camera: CameraManager

    var body: some View {
        Group {
            if camera.isAuthorized {
                ZStack {
                    CameraPreviewContainer(
                        camera: camera,
                        dotLayer: DotOverlayLayer(),
                        trackingLayer: nil,
                        reprojectionLayer: nil
                    )
                    .edgesIgnoringSafeArea(.all)

                    DebugHUDView()
                        .padding()
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .topLeading)
                }

            } else if camera.authorizationStatus == .notDetermined {
                ProgressView("Requesting Camera Access…")
                    .task { await camera.checkAuth() }

            } else {
                VStack(spacing: 16) {
                    Text("Camera access is required to use LaunchLab.")
                        .font(.headline)
                        .padding(.top, 50)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .onAppear {
            if camera.isAuthorized {
                camera.startSession()
            }
        }
        .onChange(of: camera.authorizationStatus) { newStatus in
            if newStatus == .authorized {
                camera.startSession()
            } else {
                camera.stopSession()
            }
        }
    }
}
