//
//  CameraManager.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import CoreVideo
import SwiftUI
import Combine
import simd

/// Central owner of:
/// • AVCaptureSession
/// • Frame stream
/// • VisionPipeline
/// • AutoCalibration integration
/// • Intrinsics + RS timing injection
/// • Latest VisionFrameData for UI
///
/// Runs on a dedicated high-priority background queue.
///
/// Threading Model:
/// • Capture → captureQueue
/// • Pipeline → captureQueue
/// • UI updates → main queue
///
/// All calibration updates are atomic and isolated.
final class CameraManager: NSObject, ObservableObject {

    // ============================================================
    // MARK: - Published State
    // ============================================================
    @MainActor @Published public var latestFrame: VisionFrameData?
    @MainActor @Published public var isCalibrated: Bool = false
    @MainActor @Published public var calibration: CalibrationResult?
    @MainActor @Published public var isInCalibrationMode: Bool = false
    @MainActor @Published public var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // ============================================================
    // MARK: - Internals
    // ============================================================

    private let session = AVCaptureSession()

    private let captureQueue = DispatchQueue(
        label: "com.launchlab.camera.capture",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem
    )

    private let pipeline = VisionPipeline()

    private var videoOutput: AVCaptureVideoDataOutput!
    private var device: AVCaptureDevice?

    private var intrinsics: CameraIntrinsics = .zero

    // Calibration storage location
    private let calibrationURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("calibration.json")
    }()

    // ============================================================
    // MARK: - Init
    // ============================================================
    override init() {
        super.init()
        loadPersistedCalibration()
        setupSession()
    }

    // ============================================================
    // MARK: - Authorization
    // ============================================================
    @MainActor
    func checkAuth() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }

        if authorizationStatus == .authorized {
            startSession()
        }
    }

    // ============================================================
    // MARK: - Session Setup
    // ============================================================
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            print("[CameraManager] ERROR: No camera available.")
            return
        }

        self.device = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("[CameraManager] ERROR: Cannot add camera input:", error)
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let conn = videoOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        session.commitConfiguration()
    }

    // ============================================================
    // MARK: - Session Start
    // ============================================================
    private func startSession() {
        captureQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // ============================================================
    // MARK: - Calibration Mode
    // ============================================================
    @MainActor
    public func enterCalibrationMode() {
        isInCalibrationMode = true
    }

    @MainActor
    public func exitCalibrationMode() {
        isInCalibrationMode = false
    }

    // ============================================================
    // MARK: - APPLY CALIBRATION (internal)
    // ============================================================
    private func applyCalibration(_ c: CalibrationResult) {

        // 1. Apply intrinsics
        intrinsics = CameraIntrinsics(
            fx: c.fx, fy: c.fy,
            cx: c.cx, cy: c.cy,
            width: c.width,
            height: c.height
        )

        pipeline.calibratedIntrinsics = intrinsics

        // 2. Apply RS timing model
        pipeline.rsTimingModel = c.rsTimingModel

        // 3. Tilt offsets
        pipeline.cameraTiltPitch = c.pitch
        pipeline.cameraTiltRoll  = c.roll

        // 4. Translation offset
        pipeline.cameraTranslationOffset = c.translationOffset

        // 5. Distance-to-ball scalar
        pipeline.ballDistanceMeters = c.ballDistance

        // 6. Lighting normalization
        pipeline.lightingGain = c.lightingGain

        // 7. Stability flag
        isCalibrated = c.isStable
    }

    // ============================================================
    // MARK: - PUBLIC FINALIZATION METHOD (UI → manager)
    // ============================================================
    ///
    /// This is the required missing piece.
    /// Called by CalibrationFlowView when AutoCalibration finishes.
    ///
    @MainActor
    public func finishCalibration(_ result: CalibrationResult) {
        calibration = result
        isCalibrated = result.isStable

        // Apply to pipeline + internal intrinsics
        applyCalibration(result)

        // Persist to disk
        persistCalibration(result)

        // Exit calibration mode
        isInCalibrationMode = false
    }

    // ============================================================
    // MARK: - Persistence
    // ============================================================
    private func persistCalibration(_ c: CalibrationResult) {
        do {
            let data = try JSONEncoder().encode(c)
            try data.write(to: calibrationURL, options: .atomic)
        } catch {
            print("[CameraManager] ERROR: Failed to write calibration:", error)
        }
    }

    private func loadPersistedCalibration() {
        guard let data = try? Data(contentsOf: calibrationURL) else { return }

        do {
            let c = try JSONDecoder().decode(CalibrationResult.self, from: data)
            applyCalibration(c)

            DispatchQueue.main.async {
                self.calibration = c
                self.isCalibrated = c.isStable
            }

        } catch {
            print("[CameraManager] ERROR: Failed to decode calibration:", error)
        }
    }

    // ============================================================
    // MARK: - Frame Processing
    // ============================================================
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Skip frames during calibration mode
        guard !isInCalibrationMode else { return }

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let time = pts.seconds

        let width  = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)

        // Build frame container
        let frame = VisionFrameData(
            pixelBuffer: pb,
            width: width,
            height: height,
            timestamp: time,
            intrinsics: intrinsics,
            pose: nil,
            dots: []
        )

        // Run VisionPipeline
        let out = pipeline.process(frame)

        // Publish to UI
        DispatchQueue.main.async {
            self.latestFrame = out
        }
    }
}