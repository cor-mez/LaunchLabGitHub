//
//  CameraCapture.swift
//  LaunchLab
//
//  Camera capture + format configuration only.
//  Optical regime (AE/AF/AWB) is locked exactly once,
//  explicitly, after alignment is complete.
//
//  This version introduces an explicit STREAK exposure regime.
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
            // IMPORTANT: landscape right = rows aligned with launch
            conn.videoOrientation = .landscapeRight
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
    // MARK: - EXPLICIT Camera Lock (STREAK REGIME)
    // ---------------------------------------------------------------------

    /// Call exactly once after alignment is complete.
    func lockCameraForMeasurement() {
        guard !cameraLocked, let device = videoDevice else { return }

        let desiredFPS: Double = 240
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))

        // STREAK REGIME:
        // ~2.5x frame duration → visible blur but not full washout
        let exposureDuration = CMTime(
            value: frameDuration.value * 5 / 2,
            timescale: frameDuration.timescale
        )

        // Conservative ISO ceiling to avoid ISP gain weirdness
        let maxISO = min(device.activeFormat.maxISO, 800)

        do {
            try device.lockForConfiguration()

            // 1) Select true 240 FPS format
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

            // 2) Set deterministic frame timing
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            // 3) Explicit STREAK exposure
            device.setExposureModeCustom(
                duration: exposureDuration,
                iso: maxISO,
                completionHandler: nil
            )

            // 4) Lock everything down
            device.focusMode = .locked
            device.exposureMode = .locked
            device.whiteBalanceMode = .locked

            device.unlockForConfiguration()
            cameraLocked = true

            Log.info(
                .camera,
                "Locked @ \(desiredFPS) FPS | streak exp = \(CMTimeGetSeconds(exposureDuration))s | ISO ≤ \(maxISO)"
            )

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

