import SwiftUI
import AVFoundation

struct RootView: View {
    @StateObject private var camera = CameraManager.shared

    var body: some View {
        Group {
            switch camera.authorizationStatus {

            case .authorized:
                CameraPreviewView(
                    session: camera.cameraSession,
                    intrinsics: camera.intrinsics
                )
                .edgesIgnoringSafeArea(.all)

            case .notDetermined:
                ProgressView("Requesting Camera Access…")
                    .task { await camera.checkAuth() }

            default:
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
            Task {
                if camera.authorizationStatus == .notDetermined {
                    await camera.checkAuth()
                }
            }
        }
    }
}
