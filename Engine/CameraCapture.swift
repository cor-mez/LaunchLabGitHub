//
//  CameraCapture.swift
//  LaunchLab
//
//  LIVE CAPTURE OBSERVABILITY PROVIDER (V1)
//
//  ROLE (STRICT):
//  - Configure and lock a deterministic capture regime
//  - Observe cadence + lock validity
//  - Emit frames + observability signals
//  - NEVER decide shots
//  - NEVER infer authority
//

import AVFoundation
import UIKit

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ---------------------------------------------------------------------
    // MARK: - Core Capture
    // ---------------------------------------------------------------------

    private let session = AVCaptureSession()
    private let output  = AVCaptureVideoDataOutput()
    private var videoDevice: AVCaptureDevice?

    weak var delegate: CameraFrameDelegate?

    private let captureQueue = DispatchQueue(
        label: "camera.capture.queue",
        qos: .userInitiated
    )

    // ---------------------------------------------------------------------
    // MARK: - Observability State
    // ---------------------------------------------------------------------

    private(set) var isLockedForMeasurement: Bool = false
    private(set) var estimatedFPS: Double = 0

    private var lastTimestamp: Double?
    private var frameCounter: Int = 0
    private var deltas: [Double] = []

    // Cadence warmup (do NOT treat cadence as invalid before this)
    private let cadenceWarmupSec: Double = 0.50
    private var lockTimestampSec: Double?

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

        videoDevice = camera

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
            conn.videoOrientation = .landscapeRight
            conn.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    // ---------------------------------------------------------------------
    // MARK: - Format Selection (OBSERVATIONAL)
    // ---------------------------------------------------------------------

    private func selectBestFormat(
        device: AVCaptureDevice,
        targetFPS: Double
    ) -> AVCaptureDevice.Format? {

        let supported = device.formats.compactMap { format -> AVCaptureDevice.Format? in
            for range in format.videoSupportedFrameRateRanges {
                if range.minFrameRate <= targetFPS &&
                   targetFPS <= range.maxFrameRate {
                    return format
                }
            }
            return nil
        }

        guard !supported.isEmpty else { return nil }

        // Prefer 1080p formats first
        let preferred1080 = supported.filter {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width == 1920 && d.height == 1080
        }

        let chosen: AVCaptureDevice.Format

        if let best1080 = preferred1080.sorted(by: { a, b in
            let ra = a.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            let rb = b.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            return ra > rb
        }).first {
            chosen = best1080
        } else {
            // Fallback: highest resolution that supports target FPS
            chosen = supported.sorted {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return (a.width * a.height) > (b.width * b.height)
            }.first!
        }

        let d = CMVideoFormatDescriptionGetDimensions(chosen.formatDescription)
        Log.info(
            .camera,
            "FORMAT_SELECTED res=\(d.width)x\(d.height) maxFPS=\(chosen.videoSupportedFrameRateRanges.map { $0.maxFrameRate })"
        )

        return chosen
    }

    // ---------------------------------------------------------------------
    // MARK: - Measurement Lock (CONFIGURATION ONLY)
    // ---------------------------------------------------------------------

    /// Locks the camera into a deterministic capture regime.
    /// This establishes observability — not authority.
    func lockCameraForMeasurement(targetFPS: Double = 120) {

        // 🔍 AUTHORITATIVE DIAGNOSTIC — must appear exactly once
        Log.info(.camera, "LOCK_ATTEMPT targetFPS=\(Int(targetFPS))")

        guard !isLockedForMeasurement, let device = videoDevice else {
            Log.info(.camera, "LOCK_SKIPPED alreadyLocked=\(isLockedForMeasurement)")
            return
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))

        do {
            try device.lockForConfiguration()
            guard let format = selectBestFormat(
                device: device,
                targetFPS: targetFPS
            ) else {
                Log.info(.camera, "❌ No format supports \(targetFPS) FPS")
                device.unlockForConfiguration()
                return
            }

            device.activeFormat = format
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            let exposureDuration = CMTimeMultiplyByFloat64(frameDuration, multiplier: 0.85)
            let maxISO = min(device.activeFormat.maxISO, 800)

            device.setExposureModeCustom(
                duration: exposureDuration,
                iso: maxISO,
                completionHandler: nil
            )

            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            device.exposureMode = .locked
            device.whiteBalanceMode = .locked

            // -------- LOG TRUE CAPTURE REGIME --------

            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ranges = format.videoSupportedFrameRateRanges
                .map { String(format: "[%.0f–%.0f]", $0.minFrameRate, $0.maxFrameRate) }
                .joined(separator: ",")

            Log.info(
                .camera,
                String(
                    format:
                    "📷 CAPTURE_LOCKED " +
                    "res=%dx%d " +
                    "targetFPS=%.0f " +
                    "frameDur=%.6fs " +
                    "exp=%.6fs " +
                    "ISO≤%.0f " +
                    "fpsRanges=%@",
                    dims.width,
                    dims.height,
                    targetFPS,
                    CMTimeGetSeconds(frameDuration),
                    CMTimeGetSeconds(exposureDuration),
                    maxISO,
                    ranges
                )
            )

            device.unlockForConfiguration()

            isLockedForMeasurement = true
            lockTimestampSec = CACurrentMediaTime()

        } catch {
            Log.info(.camera, "❌ Camera lock failed: \(error)")
        }
    }

    // ---------------------------------------------------------------------
    // MARK: - Control
    // ---------------------------------------------------------------------

    func start() {
        guard !session.isRunning else { return }
        captureQueue.async {
            self.session.startRunning()
            Log.info(.camera, "Camera session started")
        }
    }

    func stop() {
        guard session.isRunning else { return }
        captureQueue.async {
            self.session.stopRunning()
            Log.info(.camera, "Camera session stopped")
        }

        isLockedForMeasurement = false
        lockTimestampSec = nil
        lastTimestamp = nil
        frameCounter = 0
        deltas.removeAll()
        estimatedFPS = 0
    }

    // ---------------------------------------------------------------------
    // MARK: - Frame Delivery + Cadence Estimation (OBSERVATIONAL)
    // ---------------------------------------------------------------------

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        if let last = lastTimestamp {
            let dt = ts - last
            if dt > 0 {
                deltas.append(dt)
                if deltas.count > 12 { deltas.removeFirst() }

                if deltas.count >= 6 {
                    let avg = deltas.reduce(0, +) / Double(deltas.count)
                    estimatedFPS = 1.0 / avg
                }
            }
        }

        lastTimestamp = ts
        frameCounter += 1

        // Cadence log only after warmup
        if
            let lockT = lockTimestampSec,
            CACurrentMediaTime() - lockT >= cadenceWarmupSec,
            frameCounter % 120 == 0,
            estimatedFPS > 0
        {
            Log.info(
                .camera,
                String(format: "FPS_ESTIMATE steady=%.1f", estimatedFPS)
            )
        }

        Task { @MainActor in
            delegate?.cameraDidOutput(
                pb,
                timestamp: CMTime(
                    seconds: ts,
                    preferredTimescale: 1_000_000
                )
            )
        }
    }
}
