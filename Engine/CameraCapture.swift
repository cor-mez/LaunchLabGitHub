//
//  CameraCapture.swift
//  LaunchLab
//

import AVFoundation
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Properties
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private var videoDevice: AVCaptureDevice?

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
        session.sessionPreset = .high   // DO NOT use this to control FPS

        // Camera selection
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            return
        }

        self.videoDevice = camera

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Pixel format: REQUIRED for Y/CbCr Metal pipeline
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        if let conn = output.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    // ---------------------------------------------------------------------
    // MARK: - High-Speed Format Selection
    // ---------------------------------------------------------------------

    private func selectBestHighSpeedFormat(
        device: AVCaptureDevice,
        targetFPS: Double
    ) -> AVCaptureDevice.Format? {

        let candidates: [(AVCaptureDevice.Format, AVFrameRateRange)] =
            device.formats.compactMap { format in
                for range in format.videoSupportedFrameRateRanges {
                    if range.minFrameRate <= targetFPS &&
                       targetFPS <= range.maxFrameRate {
                        return (format, range)
                    }
                }
                return nil
            }

        // Prefer highest resolution format that supports the FPS
        return candidates
            .sorted { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.0.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.0.formatDescription)
                return (da.width * da.height) > (db.width * db.height)
            }
            .first?
            .0
    }

    // ---------------------------------------------------------------------
    // MARK: - Camera Locking (Measurement Mode)
    // ---------------------------------------------------------------------

    func lockCameraForMeasurement(device: AVCaptureDevice) {

        let desiredFPS: Double = 240

        do {
            try device.lockForConfiguration()

            // ----------------------------
            // Select a format that actually supports 240 FPS
            // ----------------------------
            if let format = selectBestHighSpeedFormat(
                device: device,
                targetFPS: desiredFPS
            ) {
                device.activeFormat = format
            } else {
                print("[CAMERA] ⚠️ No format supports \(desiredFPS) FPS on this device")
                device.unlockForConfiguration()
                return
            }

            // ----------------------------
            // Focus
            // ----------------------------
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .continuousAutoFocus
                device.focusMode = .locked
            }

            // ----------------------------
            // Exposure
            // ----------------------------
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .continuousAutoExposure
                device.exposureMode = .locked
            }

            // ----------------------------
            // White Balance
            // ----------------------------
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                device.whiteBalanceMode = .locked
            }

            // ----------------------------
            // Frame Rate (now SAFE)
            // ----------------------------
            let duration = CMTime(
                value: 1,
                timescale: CMTimeScale(desiredFPS)
            )
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration

            device.unlockForConfiguration()

            if DebugProbe.isEnabled(.capture) {
                print(
                    "[CAMERA] locked fps=\(desiredFPS) " +
                    "iso=\(device.iso) " +
                    "shutter=\(CMTimeGetSeconds(device.exposureDuration))"
                )
            }

        } catch {
            print("[CAMERA] lock failed: \(error)")
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Control
    // ---------------------------------------------------------------------

    func start() {
        guard !session.isRunning else { return }

        captureQueue.async {
            self.session.startRunning()

            // Allow AF/AE to settle, then lock
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let device = self.videoDevice {
                    self.lockCameraForMeasurement(device: device)
                }
            }
        }
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

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        Task { @MainActor in
            self.delegate?.cameraDidOutput(pb, timestamp: ts)
        }
    }
}
