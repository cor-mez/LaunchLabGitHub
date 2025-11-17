//
//  CameraManager.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

@MainActor
public final class CameraManager: NSObject, ObservableObject {

    // ---------------------------------------------------------
    // MARK: - Public API
    // ---------------------------------------------------------
    public static let shared = CameraManager()

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var permissionGranted = false

    /// Latest active intrinsics
    @Published public private(set) var intrinsics: CameraIntrinsics = .manual

    private override init() {
        super.init()
    }

    // ---------------------------------------------------------
    // MARK: - Permissions
    // ---------------------------------------------------------
    public func requestPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            return granted

        default:
            return false
        }
    }

    // ---------------------------------------------------------
    // MARK: - Start Session
    // ---------------------------------------------------------
    public func start() async {
        guard permissionGranted else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back)
        else {
            print("❌ No back camera")
            session.commitConfiguration()
            return
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Unable to create input")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        // Output
        videoOutput.setSampleBufferDelegate(self,
                                            queue: DispatchQueue(label: "cam.queue"))
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let c = videoOutput.connection(with: .video),
           c.isVideoOrientationSupported {
            c.videoOrientation = .portrait
        }

        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
    }

    // ---------------------------------------------------------
    // MARK: - Preview Layer
    // ---------------------------------------------------------
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }

    // ---------------------------------------------------------
    // MARK: - Intrinsics Extraction
    // ---------------------------------------------------------
    private func updateIntrinsics(from sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }

        let camMatrixKey = "CameraIntrinsicMatrix" as CFString

        guard let ext = CMFormatDescriptionGetExtension(formatDesc,
                                                        extensionKey: camMatrixKey)
        else { return }

        guard let dict = ext as? [String: Any],
              let data = dict["data"] as? [NSNumber],
              data.count == 9
        else { return }

        let fx = Float(truncating: data[0])
        let fy = Float(truncating: data[4])
        let cx = Float(truncating: data[2])
        let cy = Float(truncating: data[5])

        intrinsics = CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)
    }
}

// -------------------------------------------------------------
// MARK: - Delegate
// -------------------------------------------------------------
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let pb = sampleBuffer.imageBuffer else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Send to vision pipeline
        VisionPipeline.shared.processFrame(pixelBuffer: pb, timestamp: timestamp)

        // Intrinsics update → MainActor
        Task { @MainActor [weak self] in
            self?.updateIntrinsics(from: sampleBuffer)
        }
    }
}
