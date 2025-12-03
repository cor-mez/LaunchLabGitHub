//
//  CameraManager.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import ImageIO
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {

    @Published var latestPixelBuffer: CVPixelBuffer?
    @Published var latestFrame: VisionFrameData?

    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var ballLockConfig: BallLockConfig = BallLockConfig()
    @Published var unsafeLighting: Bool = false
    @Published var unsafeFrameRate: Bool = false
    @Published var unsafeThermal: Bool = false

    var onFrameDimensionsChanged: ((Int, Int) -> Void)?

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "LaunchLab.Camera.Session")

    private var pipeline: VisionPipeline!

    override init() {
        super.init()
        self.pipeline = VisionPipeline(ballLockConfig: ballLockConfig)
    }

    func checkAuth() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }
    }

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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back)
        else {
            print("❌ No back camera.")
            captureSession.commitConfiguration()
            return
        }

        // Camera input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("❌ Input error:", error)
        }

        // Video output
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

        if let conn = videoOutput.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        captureSession.commitConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                  didOutput sampleBuffer: CMSampleBuffer,
                                  from connection: AVCaptureConnection) {

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)

        // Dimensions first → overlays
        DispatchQueue.main.async { [weak self] in
            self?.onFrameDimensionsChanged?(w, h)
        }

        // Publish latest pixel buffer
        DispatchQueue.main.async { [weak self] in
            self?.latestPixelBuffer = buffer
        }

        // Extract intrinsics
        var fx: Float = 1, fy: Float = 1, cx: Float = 0, cy: Float = 0

        if let mat = CMGetAttachment(sampleBuffer,
                                     key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                     attachmentModeOut: nil) as? simd_float3x3 {
            fx = mat[0][0]
            fy = mat[1][1]
            cx = mat[2][0]
            cy = mat[2][1]
        }

        let intrinsics = CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)

        // Run VisionPipeline off-main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let frame = self.pipeline.processFrame(
                pixelBuffer: buffer,
                timestamp: timestamp,
                intrinsics: intrinsics
            )

            DispatchQueue.main.async {
                self.latestFrame = frame
            }
        }
    }
}