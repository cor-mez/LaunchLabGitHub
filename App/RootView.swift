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
            switch camera.authorizationStatus {

            case .authorized:
                ZStack {
                    // Camera feed + CALayer overlays
                    CameraPreviewView(
                        session: camera.cameraSession,
                        intrinsics: camera.intrinsics
                    )
                    .environmentObject(camera)
                    .edgesIgnoringSafeArea(.all)

                    // SwiftUI Debug HUD (no arguments now)
                    DebugHUDView()
                        .padding()
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .topLeading)
                        // We WANT taps here for the BallLock tuning button,
                        // so do NOT disable hit testing.
                }

            case .notDetermined:
                ProgressView("Requesting Camera Access…")
                    .task { await camera.checkAuth() }

            case .denied, .restricted:
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

            @unknown default:
                EmptyView()
            }
        }
        .onAppear {
            if camera.authorizationStatus == .authorized {
                camera.start()
            }
        }
        .onChange(of: camera.authorizationStatus) { newStatus in
            if newStatus == .authorized {
                camera.start()
            }
        }
    }
}
