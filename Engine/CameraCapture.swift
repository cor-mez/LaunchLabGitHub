//
//  CameraCapture.swift
//

import AVFoundation
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Properties
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()

    /// DotTestViewController gets frames through this delegate
    weak var delegate: CameraFrameDelegate?

    /// Delivery queue for frame output
    private let captureQueue = DispatchQueue(
        label: "camera.capture.queue",
        qos: .userInitiated
    )

    // ---------------------------------------------------------------------
    // MARK: - Init
    // ---------------------------------------------------------------------

    override init() {
        super.init()
        configureSession()
    }

    // ---------------------------------------------------------------------
    // MARK: - Session Setup
    // ---------------------------------------------------------------------

    private func configureSession() {

        session.beginConfiguration()
        session.sessionPreset = .high     // stable 720p → 1080p range

        // Camera selection
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Pixel format: REQUIRED for Y→Metal conversion
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Force portrait orientation
        if let conn = output.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    // ---------------------------------------------------------------------
    // MARK: - Control
    // ---------------------------------------------------------------------

    func start() {
        guard !session.isRunning else { return }
        captureQueue.async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        captureQueue.async { self.session.stopRunning() }
    }

    // ---------------------------------------------------------------------
    // MARK: - Frame Delivery
    // ---------------------------------------------------------------------

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        // Extract pixel buffer
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Debug fourCC
        if let desc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let fourCC = CMFormatDescriptionGetMediaSubType(desc)

            // Portable 4-char formatter
            let c1 = Character(UnicodeScalar((fourCC >> 24) & 0xFF)!)
            let c2 = Character(UnicodeScalar((fourCC >> 16) & 0xFF)!)
            let c3 = Character(UnicodeScalar((fourCC >> 8)  & 0xFF)!)
            let c4 = Character(UnicodeScalar( fourCC        & 0xFF)!)

        }

        // Deliver to main thread → DotTestViewController
        Task { @MainActor in
            self.delegate?.cameraDidOutput(pb)
        }
    }
}
