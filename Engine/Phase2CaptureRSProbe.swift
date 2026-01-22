//
//  Phase2CaptureRSProbe.swift
//  LaunchLab
//
//  PHASE 2 — Capture + RS observability
//
//  PURPOSE:
//  - Confirm RS physics exists in single frames
//  - No authority
//  - No lifecycle
//

import AVFoundation
import CoreMedia

final class Phase2CaptureRSProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private let queue   = DispatchQueue(
        label: "phase2.capture.queue",
        qos: .userInteractive
    )

    private let rsProbe = RSObservabilityProbe()

    func start(targetFPS: Double = 120) {
        queue.async {
            self.configureSession(targetFPS: targetFPS)
            self.session.startRunning()
            print("🧪 Phase2 RS probe running @\(Int(targetFPS))fps")
        }
    }

    private func configureSession(targetFPS: Double) {

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ),
        let input = try? AVCaptureDeviceInput(device: device)
        else {
            fatalError("Camera unavailable")
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        try? device.lockForConfiguration()

        let frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(targetFPS)
        )

        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        device.unlockForConfiguration()
        session.commitConfiguration()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        SignpostTrace.beginFrame()

        // NOTE:
        // This is where FAST9 / corner extraction would feed points.
        // For Phase 2, points should come from your existing detector.

        let dummyPoints: [CGPoint] = []   // replaced by real detector

        _ = rsProbe.evaluate(
            points: dummyPoints,
            imageHeight: 1080
        )

        SignpostTrace.endFrame()
    }
}
