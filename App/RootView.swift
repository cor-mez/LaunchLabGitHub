import SwiftUI
import AVFoundation

struct RootView: View {

    @EnvironmentObject private var camera: CameraManager

    var body: some View {
        Group {
            switch camera.authorizationStatus {

            case .authorized:
                CameraPreviewView()
                    .environmentObject(camera)
                    .edgesIgnoringSafeArea(.all)

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
            Task {
                if camera.authorizationStatus == .notDetermined {
                    await camera.checkAuth()
                }
            }
        }
    }
}
