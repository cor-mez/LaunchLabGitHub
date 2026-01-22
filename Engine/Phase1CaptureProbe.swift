//
//  Phase1CaptureProbe.swift
//  LaunchLab
//
//  PHASE 1 — Clean-room capture cadence probe
//
//  PURPOSE:
//  - Measure delivered CMSampleBuffer cadence
//  - No rendering
//  - No Metal
//  - No RS
//  - No logging except Δt + FPS
//

import AVFoundation
import CoreMedia

final class Phase1CaptureProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Core Capture

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private let queue   = DispatchQueue(label: "phase1.capture.queue",
                                        qos: .userInteractive)

    // MARK: - Timing

    private var lastTimestamp: Double?
    private var deltas: [Double] = []

    private let windowSize = 120   // ~1s at 120fps

    // MARK: - Public API

    func start(targetFPS: Double = 120) {
        configureSession(targetFPS: targetFPS)

        queue.async { [weak self] in
            self?.session.startRunning()
            print("🚀 Phase1 capture started (targetFPS=\(Int(targetFPS)))")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
            print("🛑 Phase1 capture stopped")
        }
    }

    // MARK: - Session Setup

    private func configureSession(targetFPS: Double) {

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            fatalError("No camera device")
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Failed to create input")
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

        let frameDuration = CMTime(value: 1,
                                   timescale: CMTimeScale(targetFPS))

        if let format = bestFormat(device: device, targetFPS: targetFPS) {
            device.activeFormat = format
        }

        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration

        device.unlockForConfiguration()

        session.commitConfiguration()
    }

    private func bestFormat(device: AVCaptureDevice,
                            targetFPS: Double) -> AVCaptureDevice.Format? {

        let candidates = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= targetFPS &&
                targetFPS <= $0.maxFrameRate
            }
        }

        return candidates.min {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return (a.width * a.height) < (b.width * b.height)
        }
    }

    // MARK: - Capture Delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        if let last = lastTimestamp {
            let dt = ts - last
            if dt > 0 {
                deltas.append(dt)
                if deltas.count > windowSize {
                    deltas.removeFirst()
                }

                if deltas.count == windowSize {
                    let avg = deltas.reduce(0, +) / Double(deltas.count)
                    let fps = 1.0 / avg
                    print(String(format: "Δt=%.4f  FPS≈%.1f", dt, fps))
                } else {
                    print(String(format: "Δt=%.4f", dt))
                }
            }
        }

        lastTimestamp = ts
    }
}
