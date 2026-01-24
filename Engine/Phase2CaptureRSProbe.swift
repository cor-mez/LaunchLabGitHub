//
//  Phase2CaptureRSProbe.swift
//  LaunchLab
//
//  PHASE 2 — Capture + RS observability (TRUTH-FIRST, LOCKED)
//
//  ROLE (STRICT):
//  - Headless (no UI, no preview)
//  - Single-frame RS observability only
//  - No authority
//  - No lifecycle
//  - No synthetic signal
//  - Deterministic capture regime
//

import AVFoundation
import CoreMedia
import CoreGraphics
import QuartzCore

final class Phase2CaptureRSProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Capture Core
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()

    private let queue = DispatchQueue(
        label: "phase2.capture.queue",
        qos: .userInteractive
    )

    private var videoDevice: AVCaptureDevice?

    // ---------------------------------------------------------------------
    // MARK: - Observers (OBSERVATION ONLY)
    // ---------------------------------------------------------------------

    private let detector = MetalDetector.shared
    private let rsProbe  = RSObservabilityProbe()

    // ---------------------------------------------------------------------
    // MARK: - Public API
    // ---------------------------------------------------------------------

    func start(targetFPS: Double = 120) {
        queue.async {
            self.configureSession(targetFPS: targetFPS)
            self.session.startRunning()
            print("🧪 Phase 2 RS Observability Probe running — headless, locked capture")
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

        videoDevice = device

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

        lockCaptureRegime(device: device, targetFPS: targetFPS)
        session.commitConfiguration()
    }

    // ---------------------------------------------------------------------
    // MARK: - Deterministic Capture Lock
    // ---------------------------------------------------------------------

    private func lockCaptureRegime(
        device: AVCaptureDevice,
        targetFPS: Double
    ) {

        do {
            try device.lockForConfiguration()

            guard let format = device.formats.first(where: {
                $0.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= targetFPS &&
                    targetFPS <= $0.maxFrameRate
                }
            }) else {
                fatalError("No format supports \(targetFPS) FPS")
            }

            device.activeFormat = format

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            let exposure = CMTimeMultiplyByFloat64(frameDuration, multiplier: 0.10)
            let iso = min(format.maxISO, 800)

            device.setExposureModeCustom(duration: exposure, iso: iso, completionHandler: nil)

            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }

            device.exposureMode = .locked
            device.whiteBalanceMode = .locked

            device.unlockForConfiguration()

            TelemetryRingBuffer.shared.push(
                phase: .camera,
                code: 0x60,
                valueA: Float(exposure.seconds),
                valueB: Float(iso)
            )

        } catch {
            fatalError("Failed to lock capture regime: \(error)")
        }
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
                code: 0xEE
            )
            return
        }

        let fullROI = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        // -----------------------------------------------------------------
        // FAST9 → RS (CORRECT APIs)
        // -----------------------------------------------------------------

        detector.prepareFrameY(
            pixelBuffer,
            roi: fullROI,
            srScale: 1.0
        ) { [weak self] scoredPoints in
            guard let self else { return }

            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x41,
                valueA: Float(scoredPoints.count),
                valueB: 0
            )

            let rsPoints = scoredPoints.map { $0.point }

            let observation = self.rsProbe.evaluate(
                points: rsPoints,
                imageHeight: CVPixelBufferGetHeight(pixelBuffer),
                timestamp: timestamp
            )

            TelemetryRingBuffer.shared.push(
                phase: .detection,
                code: 0x42,
                valueA: observation.zmax,
                valueB: Float(observation.validRowCount)
            )
        }
    }
}
