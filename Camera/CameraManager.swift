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
    // MARK: - Singleton
    // ---------------------------------------------------------
    public static let shared = CameraManager()

    // ---------------------------------------------------------
    // MARK: - Capture Properties
    // ---------------------------------------------------------
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Public getter for UI
    public var cameraSession: AVCaptureSession { session }

    // ---------------------------------------------------------
    // MARK: - Authorization
    // ---------------------------------------------------------
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    public func checkAuth() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        switch status {
        case .authorized:
            return

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied

        default:
            return
        }
    }

    // ---------------------------------------------------------
    // MARK: - Intrinsics (Updated each frame)
    // ---------------------------------------------------------
    @Published public private(set) var intrinsics =
        CameraIntrinsics.zero

    // ---------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------
    private override init() {
        super.init()
    }

    // ---------------------------------------------------------
    // MARK: - Start Session
    // ---------------------------------------------------------
    public func start() async {
        guard authorizationStatus == .authorized else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Camera device
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            print("❌ No back camera available")
            session.commitConfiguration()
            return
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Unable to create camera input")
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

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
    }

    // ---------------------------------------------------------
    // MARK: - Preview Layer (UI Convenience)
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
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        let key = "CameraIntrinsicMatrix" as CFString

        guard let ext = CMFormatDescriptionGetExtension(formatDesc, extensionKey: key),
              let dict = ext as? [String: Any],
              let data = dict["data"] as? [NSNumber],
              data.count == 9
        else { return }

        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)

        let fx = Float(truncating: data[0])
        let fy = Float(truncating: data[4])
        let cx = Float(truncating: data[2])
        let cy = Float(truncating: data[5])

        intrinsics = CameraIntrinsics(
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy,
            width: Int(dims.width),
            height: Int(dims.height)
        )
    }
}

// -------------------------------------------------------------
// MARK: - SampleBuffer Delegate (Nonisolated)
// -------------------------------------------------------------
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let pb = sampleBuffer.imageBuffer else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // VisionPipeline is @MainActor → hop to main
        Task { @MainActor in
            VisionPipeline.shared.process(pixelBuffer: pb, timestamp: timestamp)
        }

        // Update intrinsics (also requires MainActor)
        Task { @MainActor [weak self] in
            self?.updateIntrinsics(from: sampleBuffer)
        }
    }
}
