import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import SwiftUI
import simd

@MainActor
final class CameraManager: NSObject, ObservableObject {

    @Published var latestWeakPixelBuffer = WeakPixelBuffer(nil)
    @Published var latestFrame: VisionFrameData?
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var ballLockConfig = BallLockConfig()
    @Published var unsafeLighting = false
    @Published var unsafeFrameRate = false
    @Published var unsafeThermal = false

    var onFrameDimensionsChanged: ((Int, Int) -> Void)?

    private let session = AVCaptureSession()
    var captureSession: AVCaptureSession { session }

    var isAuthorized: Bool { authorizationStatus == .authorized }

    nonisolated(unsafe) var enableProcessing: Bool = false
    nonisolated(unsafe) var enableFramePublishing: Bool = false

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "LaunchLab.Camera.Session")
    private var pipeline: VisionPipeline!

    override init() {
        super.init()
        pipeline = VisionPipeline(ballLockConfig: ballLockConfig)
    }

    func checkAuth() async {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = s
        if s == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }
    }

    func startSession() {
        guard isAuthorized else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: dev)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            return
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        let q = DispatchQueue(label: "LaunchLab.Camera.Output")
        output.setSampleBufferDelegate(self, queue: q)

        if session.canAddOutput(output) { session.addOutput(output) }

        if let c = output.connection(with: .video), c.isVideoOrientationSupported {
            c.videoOrientation = .portrait
        }

        session.commitConfiguration()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sb: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onFrameDimensionsChanged?(w, h)
            self.latestWeakPixelBuffer = WeakPixelBuffer(pb)
        }

        var fx: Float = 1
        var fy: Float = 1
        var cx: Float = 0
        var cy: Float = 0

        if let m = CMGetAttachment(
            sb,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? simd_float3x3 {
            fx = m[0][0]
            fy = m[1][1]
            cx = m[2][0]
            cy = m[2][1]
        }

        let intr = CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)

        if enableProcessing {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let frame = self.pipeline.processFrame(
                    pixelBuffer: pb,
                    timestamp: t,
                    intrinsics: intr
                )
                DispatchQueue.main.async {
                    if self.enableFramePublishing {
                        self.latestFrame = frame
                    }
                }
            }
        }
    }
}
