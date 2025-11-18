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
private let hudLayer = HUDOverlayLayer()
    // ---------------------------------------------------------
    // MARK: - Pipeline Ownership (NO SINGLETONS)
    // ---------------------------------------------------------
    let pipeline = VisionPipeline()

    // ---------------------------------------------------------
    // MARK: - Capture Properties
    // ---------------------------------------------------------
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

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
    // MARK: - Intrinsics
    // ---------------------------------------------------------
    @Published public private(set) var intrinsics = CameraIntrinsics.zero

    // ---------------------------------------------------------
    // MARK: - Latest Processed Frame (For Overlays)
    // ---------------------------------------------------------
    @Published private(set) var latestFrame: VisionFrameData?

    // ---------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------
    public override init() {
    super.init()
    hudLayer.camera = self
}

    // ---------------------------------------------------------
    // MARK: - Start Session
    // ---------------------------------------------------------
    public func start() async {
        guard authorizationStatus == .authorized else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            print("❌ No back camera available")
            session.commitConfiguration()
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Unable to create camera input")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        videoOutput.setSampleBufferDelegate(
            self,
            queue: DispatchQueue(label: "cam.queue")
        )

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

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
    // MARK: - Preview Layer
    // ---------------------------------------------------------
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
        
        if let view = context.coordinator.view {
    hudLayer.frame = view.bounds
    view.layer.addSublayer(hudLayer)
}
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
            fx: fx, fy: fy,
            cx: cx, cy: cy,
            width: Int(dims.width),
            height: Int(dims.height)
        )
    }
}


// ---------------------------------------------------------
// MARK: - SampleBuffer Delegate
// ---------------------------------------------------------

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = sampleBuffer.imageBuffer else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let width  = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)

        // Hop to MainActor for VisionPipeline processing
        Task { @MainActor in
            let frame = VisionFrameData(
                pixelBuffer: pb,
                width: width,
                height: height,
                timestamp: ts,
                intrinsics: self.intrinsics,
                pose: nil,
                dots: []
            )

            // Correct v4 API
            let processed = self.pipeline.process(frame)
            // Publish for overlays
            self.hudLayer.setNeedsDisplay()
        }

        // Update intrinsics separately
        Task { @MainActor [weak self] in
            self?.updateIntrinsics(from: sampleBuffer)
        }
    }
}
