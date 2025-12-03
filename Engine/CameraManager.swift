//
//  CameraManager.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import ImageIO        // ← REQUIRED for kCGImagePropertyCameraIntrinsicMatrix
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // ============================================================
    // MARK: - Published (SwiftUI-visible)
    // ============================================================

    @Published var latestPixelBuffer: CVPixelBuffer?
    @Published var latestFrame: VisionFrameData?

    /// Camera authorization for RootView
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    public var isAuthorized: Bool { authorizationStatus == .authorized }

    /// BallLock tuning (UI-driven)
    @Published var ballLockConfig: BallLockConfig = BallLockConfig()

    /// Safety state flags
    @Published var unsafeLighting: Bool = false
    @Published var unsafeFrameRate: Bool = false
    @Published var unsafeThermal: Bool = false

    // ============================================================
    // MARK: - Callbacks
    // ============================================================

    /// Called whenever the camera reports new buffer size (width/height)
    var onFrameDimensionsChanged: ((Int, Int) -> Void)?

    // ============================================================
    // MARK: - AVCapture Session
    // ============================================================

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "LaunchLab.Camera.Session")

    // ============================================================
    // MARK: - Vision Pipeline
    // ============================================================

    private var pipeline: VisionPipeline!

    override init() {
        super.init()
        self.pipeline = VisionPipeline(ballLockConfig: ballLockConfig)
    }

    // ============================================================
    // MARK: - Authorization
    // ============================================================

    func checkAuth() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }
    }

    // ============================================================
    // MARK: - Session Setup
    // ============================================================

    func startSession() {
        guard isAuthorized else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.inputs.isEmpty {
                self.configureSession()
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        // Camera device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back)
        else {
            print("❌ No back camera available.")
            captureSession.commitConfiguration()
            return
        }

        // Device Input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("❌ Failed to create AVCaptureDeviceInput:", error)
        }

        // Video Output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        let outputQueue = DispatchQueue(label: "LaunchLab.Camera.Output")
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Orientation
        if let conn = videoOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()
    }
}


// ============================================================================
// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// ============================================================================

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
    {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // -----------------------------------------------------
        // Notify overlays of buffer dimension changes
        // -----------------------------------------------------
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        if let cb = onFrameDimensionsChanged {
            cb(w, h)
        }

        // Publish pixel buffer (DotTestMode & overlays rely on this)
        DispatchQueue.main.async {
            self.latestPixelBuffer = buffer
        }

        // -----------------------------------------------------
        // Intrinsics extraction
        // -----------------------------------------------------
        var fx: Float = 1
        var fy: Float = 1
        var cx: Float = 0
        var cy: Float = 0

        if let mat = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? simd_float3x3 {
            fx = mat[0][0]
            fy = mat[1][1]
            cx = mat[2][0]
            cy = mat[2][1]
        }

        let intrinsics = CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)

        // -----------------------------------------------------
        // Vision Pipeline Execution
        // -----------------------------------------------------
        let frame = pipeline.processFrame(
            pixelBuffer: buffer,
            timestamp: timestamp,
            intrinsics: intrinsics
        )

        DispatchQueue.main.async {
            self.latestFrame = frame
        }
    }
}
