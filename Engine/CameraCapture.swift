//
//  CameraCapture.swift
//  LaunchLab
//
//  Deterministic high-speed capture for RS metrology.
//  No detection logic.
//  No UI assumptions.
//  Physics-first configuration.
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

        // Do NOT use ambiguous presets for RS work
        session.sessionPreset = .inputPriority

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

            // CRITICAL: RS physics prefers landscape geometry
            conn.videoOrientation = .landscapeRight
            conn.isVideoMirrored = false

            // Disable stabilization if present
            if conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .off
            }
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
    // MARK: - Explicit Camera Lock (Call Once)
    // ---------------------------------------------------------------------

    /// Call exactly once after alignment is complete.
    /// Sets deterministic timing + exposure for RS measurement.
    func lockCameraForMeasurement() {

        guard !cameraLocked, let device = videoDevice else { return }

        let desiredFPS: Double = 240

        do {
            try device.lockForConfiguration()

            guard let format = selectBestHighSpeedFormat(
                device: device,
                targetFPS: desiredFPS
            ) else {
                Log.info(.camera, "No format supports \(desiredFPS) FPS")
                device.unlockForConfiguration()
                return
            }

            device.activeFormat = format

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            // -------------------------------
            // STREAK-FRIENDLY EXPOSURE REGIME
            // -------------------------------

            // ~1/720 sec exposure as a starting point
            let exposureDuration = CMTime(value: 1, timescale: 720)

            let iso = min(
                max(device.activeFormat.minISO, 200),
                device.activeFormat.maxISO
            )

            if device.isExposureModeSupported(.custom) {
                device.setExposureModeCustom(
                    duration: exposureDuration,
                    iso: iso,
                    completionHandler: nil
                )
            }

            // Lock focus & WB after exposure is set
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }

            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }

            device.unlockForConfiguration()
            cameraLocked = true

            Log.info(
                .camera,
                "Camera locked: \(desiredFPS) fps, landscape, exp=\(exposureDuration.seconds)s ISO=\(iso)"
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
