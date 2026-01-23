//
//  Phase2CaptureRSProbe.swift
//  LaunchLab
//
//  PHASE 2 — Capture + RS observability (CRASH-SAFE)
//
//  ROLE (STRICT):
//  - Single-frame RS observability only
//  - No authority
//  - No lifecycle
//  - Telemetry-only
//  - No synthetic data
//  - FPS is negotiated, never assumed
//

import AVFoundation
import CoreMedia
import CoreGraphics
import CoreVideo

final class Phase2CaptureRSProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Capture
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private let queue   = DispatchQueue(label: "phase2.capture.queue", qos: .userInteractive)

    // ---------------------------------------------------------------------
    // MARK: - Observers
    // ---------------------------------------------------------------------

    private let detector = MetalDetector.shared
    private let rsProbe  = RSObservabilityProbe()

    // ---------------------------------------------------------------------
    // MARK: - Public
    // ---------------------------------------------------------------------

    func start(requestedFPS: Double = 120) {
        queue.async {
            self.configureSession(requestedFPS: requestedFPS)
            self.session.startRunning()
            print("🧪 Phase 2 RS Observability Probe running — headless, no UI")
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Session Configuration
    // ---------------------------------------------------------------------

    private func configureSession(requestedFPS: Double) {

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            fatalError("Phase2CaptureRSProbe: camera unavailable")
        }

        if session.canAddInput(input) { session.addInput(input) }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) { session.addOutput(output) }

        // -------------------------------------------------------------
        // FPS NEGOTIATION (CRASH-SAFE)
        // -------------------------------------------------------------

        let negotiatedFPS = selectAndApplyBestFormat(
            device: device,
            requestedFPS: requestedFPS
        )

        TelemetryRingBuffer.shared.push(
            phase: .camera,
            code: 0x01,                       // negotiated FPS
            valueA: Float(requestedFPS),
            valueB: Float(negotiatedFPS)
        )

        session.commitConfiguration()
    }

    /// Selects a format that supports the requested FPS (or the closest lower),
    /// applies it safely, and returns the actual FPS in effect.
    private func selectAndApplyBestFormat(
        device: AVCaptureDevice,
        requestedFPS: Double
    ) -> Double {

        let formats = device.formats.compactMap { format -> (AVCaptureDevice.Format, Double)? in
            let maxFPS = format.videoSupportedFrameRateRanges
                .map { $0.maxFrameRate }
                .max() ?? 0
            guard maxFPS >= 1 else { return nil }
            return (format, maxFPS)
        }

        // Choose the fastest format <= requestedFPS, else the fastest overall
        let chosen = formats
            .filter { $0.1 >= requestedFPS }
            .min(by: { $0.1 < $1.1 })
            ?? formats.max(by: { $0.1 < $1.1 })

        guard let (format, maxFPS) = chosen else {
            return 0
        }

        let actualFPS = min(requestedFPS, maxFPS)

        do {
            try device.lockForConfiguration()

            device.activeFormat = format

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(actualFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            device.unlockForConfiguration()
        } catch {
            // Fail safely — never crash
            return 0
        }

        return actualFPS
    }

    // ---------------------------------------------------------------------
    // MARK: - Capture Delegate
    // ---------------------------------------------------------------------

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            TelemetryRingBuffer.shared.push(phase: .detection, code: 0xEE, valueA: 0, valueB: 0)
            return
        }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let fullROI = CGRect(x: 0, y: 0, width: w, height: h)

        TelemetryRingBuffer.shared.push(
            phase: .detection,
            code: 0x40,
            valueA: Float(w),
            valueB: Float(h)
        )

        detector.prepareFrameY(pixelBuffer, roi: fullROI, srScale: 1.0) { [weak self] in
            guard let self else { return }

            self.detector.gpuFast9ScoredCornersY { metalPoints in

                let count = metalPoints.count
                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x41,
                    valueA: Float(count),
                    valueB: 0
                )

                let rsPoints = metalPoints.map { $0.point }

                let obs = self.rsProbe.evaluate(
                    points: rsPoints,
                    imageHeight: h,
                    timestamp: ts
                )

                let outcomeCode: UInt16 = {
                    switch obs.outcome {
                    case .observable: return 0
                    case .refused(let r): return r.rawValue
                    }
                }()

                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x42,
                    valueA: obs.zmax,
                    valueB: Float(obs.validRowCount)
                )

                TelemetryRingBuffer.shared.push(
                    phase: .detection,
                    code: 0x43,
                    valueA: Float(outcomeCode),
                    valueB: 0
                )
            }
        }
    }
}
