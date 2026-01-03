//
//  CameraCapture.swift
//  LaunchLab
//
//  Camera capture + format configuration only.
//  Optical regime (AE/AF/AWB) is locked exactly once,
//  explicitly, after alignment is complete.
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

    weak var delegate: CameraFrameDelegate?

    private let captureQueue = DispatchQueue(
        label: "camera.capture.queue",
        qos: .userInitiated
    )

    private var cameraLocked = false

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
        session.sessionPreset = .high

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

        let candidates = device.formats.compactMap { format -> AVCaptureDevice.Format? in
            for range in format.videoSupportedFrameRateRanges {
                if range.minFrameRate <= targetFPS &&
                   targetFPS <= range.maxFrameRate {
                    return format
                }
            }
            return nil
        }

        return candidates.sorted {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return (a.width * a.height) > (b.width * b.height)
        }.first
    }

    // ---------------------------------------------------------------------
    // MARK: - EXPLICIT Camera Lock (Called Once)
    // ---------------------------------------------------------------------

    /// Call exactly once after alignment is complete.
    func lockCameraForMeasurement() {
        guard !cameraLocked, let device = videoDevice else { return }

        let desiredFPS: Double = 240

        do {
            try device.lockForConfiguration()

            if let format = selectBestHighSpeedFormat(
                device: device,
                targetFPS: desiredFPS
            ) {
                device.activeFormat = format
            } else {
                Log.info(.camera, "No format supports \(desiredFPS) FPS")
                device.unlockForConfiguration()
                return
            }

            // Let auto modes settle BEFORE lock (caller ensures scene is stable)
            device.focusMode = .continuousAutoFocus
            device.exposureMode = .continuousAutoExposure
            device.whiteBalanceMode = .continuousAutoWhiteBalance

            device.focusMode = .locked
            device.exposureMode = .locked
            device.whiteBalanceMode = .locked

            let duration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration

            device.unlockForConfiguration()
            cameraLocked = true

            Log.info(.camera, "AE/AF/AWB locked @ \(desiredFPS) FPS")

        } catch {
            Log.info(.camera, "Camera lock failed: \(error)")
        }
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
        cameraLocked = false
    }

    // ---------------------------------------------------------------------
    // MARK: - Frame Delivery
    // ---------------------------------------------------------------------

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        Task { @MainActor in
            self.delegate?.cameraDidOutput(pb, timestamp: ts)
        }
    }
}
