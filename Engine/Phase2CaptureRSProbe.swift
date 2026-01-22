//
//  Phase2CaptureRSProbe.swift
//  LaunchLab
//
//  PHASE 2 — Capture + RS observability (WIRING VERIFICATION)
//
//  ROLE (STRICT):
//  - Single-frame RS observability only
//  - No authority
//  - No lifecycle
//  - Telemetry-only
//

import AVFoundation
import CoreMedia
import CoreGraphics

final class Phase2CaptureRSProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Capture
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private let queue   = DispatchQueue(
        label: "phase2.capture.queue",
        qos: .userInteractive
    )

    // ---------------------------------------------------------------------
    // MARK: - Observers
    // ---------------------------------------------------------------------

    private let detector = MetalDetector.shared
    private let rsProbe  = RSObservabilityProbe()

    // ---------------------------------------------------------------------
    // MARK: - Lifecycle
    // ---------------------------------------------------------------------

    func start(targetFPS: Double = 120) {
        queue.async {
            self.configureSession(targetFPS: targetFPS)
            self.session.startRunning()
            print("🧪 Phase2 RS wiring probe running @\(Int(targetFPS))fps")
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Session Configuration
    // ---------------------------------------------------------------------

    private func configureSession(targetFPS: Double) {

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            fatalError("Phase2CaptureRSProbe: camera unavailable")
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

        if let format = device.formats.first(where: {
            $0.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= targetFPS &&
                targetFPS <= $0.maxFrameRate
            }
        }) {
            device.activeFormat = format
        }

        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        device.unlockForConfiguration()
        session.commitConfiguration()
    }

    // ---------------------------------------------------------------------
    // MARK: - Capture Delegate
    // ---------------------------------------------------------------------

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0xEE,   // frame integrity failure
                valueA: 0,
                valueB: 0
            )
            return
        }

        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        // -----------------------------------------------------------------
        // FAST9 boundary (FULL-FRAME ROI — WIRING PROBE)
        // -----------------------------------------------------------------

        let fullROI = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        detector.prepareFrameY(
            pixelBuffer,
            roi: fullROI,
            srScale: 1.0
        ) { [weak self] in
            guard let self else { return }

            self.detector.gpuFast9ScoredCornersY { metalPoints in

                // 🔍 FAST9 callback confirmed
                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x41,                      // FAST9 callback
                    valueA: Float(metalPoints.count),
                    valueB: 0
                )

                // -------------------------------------------------------------
                // TEMPORARY SYNTHETIC FALLBACK (DELETE AFTER VERIFICATION)
                // -------------------------------------------------------------

                let rsPoints: [CGPoint]
                if metalPoints.isEmpty {
                    rsPoints = [
                        CGPoint(x: 10, y: 10),
                        CGPoint(x: 20, y: 12),
                        CGPoint(x: 30, y: 14),
                        CGPoint(x: 40, y: 16),
                        CGPoint(x: 50, y: 18),
                        CGPoint(x: 60, y: 20)
                    ]
                } else {
                    rsPoints = metalPoints.map { $0.point }
                }

                // -------------------------------------------------------------
                // RS observability (MANDATORY CLASSIFICATION)
                // -------------------------------------------------------------

                let observation = self.rsProbe.evaluate(
                    points: rsPoints,
                    imageHeight: imageHeight,
                    timestamp: timestamp
                )

                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x42,                      // RS classified
                    valueA: observation.zmax,
                    valueB: Float(observation.validRowCount)
                )
            }
        }
    }
}
