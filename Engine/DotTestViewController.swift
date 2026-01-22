//
//  DotTestViewController.swift
//  LaunchLab
//
//  CAMERA DIAGNOSTIC VIEW
//
//  PURPOSE:
//  - Prove camera feed is alive
//  - Bypass Metal entirely
//  - Keep observability pipeline running
//

import UIKit
import AVFoundation
import CoreMedia

@MainActor
final class DotTestViewController: UIViewController, CameraFrameDelegate {

    private let camera = CameraCapture()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // 🔍 Attach preview layer
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        // 🔑 Wire camera
        camera.delegate = self
        previewLayer.session = cameraValueSession()

        camera.start()
        camera.lockCameraForMeasurement(targetFPS: 120)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    // ---------------------------------------------------------
    // MARK: - CameraFrameDelegate
    // ---------------------------------------------------------

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Still feed observability — no UI dependency
        DotTestCoordinator.shared.processFrame(
            pixelBuffer,
            timestamp: timestamp
        )
    }

    // ---------------------------------------------------------
    // MARK: - Session Access
    // ---------------------------------------------------------

    private func cameraValueSession() -> AVCaptureSession {
        // CameraCapture owns the session internally,
        // but AVCaptureVideoPreviewLayer needs access.
        // This is safe for diagnostics.
        let mirror = Mirror(reflecting: camera)
        for child in mirror.children {
            if let session = child.value as? AVCaptureSession {
                return session
            }
        }
        fatalError("Camera session not found")
    }
}
