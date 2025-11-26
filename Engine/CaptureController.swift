//
//  CaptureController.swift
//  LaunchLab
//
//  Nonisolated controller responsible for configuring and running
//  the AVCaptureSession entirely off the main thread.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import UIKit

final class CaptureController: NSObject {

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------

    /// Nonisolated reference to the running session.
    /// CameraPreviewView reads from this.
    let session = AVCaptureSession()

    /// Called every time a pixel buffer is captured.
    /// CameraManager installs this closure.
    var onFrame: ((CVPixelBuffer, Double) -> Void)?

    /// Called once intrinsics are known.
    var onIntrinsicsReady: ((CameraIntrinsics) -> Void)?

    // ------------------------------------------------------------
    // MARK: - Internals
    // ------------------------------------------------------------

    private let captureQueue = DispatchQueue(label: "com.launchlab.capture")
    private var videoOutput: AVCaptureVideoDataOutput?

    // ------------------------------------------------------------
    // MARK: - Start / Stop
    // ------------------------------------------------------------

    func configureAndStart() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.session.startRunning()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // ------------------------------------------------------------
    // MARK: - Session Configuration (Background Thread)
    // ------------------------------------------------------------

    private func configureSession() {

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        // Device
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            return
        }

        // 240 FPS
        do {
            try device.lockForConfiguration()
            if let format = best240FPSFormat(device: device) {
                device.activeFormat = format
                let dur = CMTimeMake(value: 1, timescale: 240)
                device.activeVideoMinFrameDuration = dur
                device.activeVideoMaxFrameDuration = dur
            }
            device.unlockForConfiguration()
        } catch {
            session.commitConfiguration()
            return
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        self.videoOutput = output

        if let conn = output.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = false
        }

        // Intrinsics extraction (now lives here)
        extractIntrinsics(from: device)

        session.commitConfiguration()
    }

    // ------------------------------------------------------------
    // MARK: - Intrinsics
    // ------------------------------------------------------------

    private func extractIntrinsics(from device: AVCaptureDevice) {
        let desc = device.activeFormat.formatDescription

        guard
            let extDict = CMFormatDescriptionGetExtensions(desc) as? [String: Any],
            let matrixData = extDict["CameraIntrinsicMatrix"] as? Data
        else {
            return
        }

        let floats: [Float] = matrixData.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }

        guard floats.count == 9 else { return }

        let fx = floats[0]
        let fy = floats[4]
        let cx = floats[2]
        let cy = floats[5]

        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        let wL = Float(dims.width)

        // Convert landscape-right → portrait-up
        let intr = CameraIntrinsics(
            fx: fy,
            fy: fx,
            cx: cy,
            cy: wL - cx
        )

        onIntrinsicsReady?(intr)
    }

    // ------------------------------------------------------------
    // MARK: - Best 240 FPS Format
    // ------------------------------------------------------------

    private func best240FPSFormat(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= 240 && dims.height == 1080 {
                    return format
                }
            }
        }
        return nil
    }
}

// ------------------------------------------------------------
// MARK: - SampleBuffer Delegate
// ------------------------------------------------------------

extension CaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CACurrentMediaTime()

        // Deliver to CameraManager (background → main not forced)
        onFrame?(pixelBuffer, t)
    }
}
