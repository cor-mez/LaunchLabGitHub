// File: Engine/CameraManager.swift
//
//  CameraManager.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Published state for UI / overlays

    @Published private(set) var latestFrame: VisionFrameData?

    @Published private(set) var unsafeLighting: Bool = false
    @Published private(set) var unsafeFrameRate: Bool = false
    @Published private(set) var unsafeThermal: Bool = false

    // Camera permission state for RootView.
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // Live BallLock tuning config (used by BallLockTuningPanel).
    @Published var ballLockConfig: BallLockConfig

    // Public accessors used by SwiftUI views.
    var cameraSession: AVCaptureSession { session }
    var intrinsics: CameraIntrinsics { currentIntrinsics }

    // MARK: - Capture session

    let session: AVCaptureSession
    private let videoOutput: AVCaptureVideoDataOutput
    private let captureQueue: DispatchQueue

    private var videoDevice: AVCaptureDevice?

    // MARK: - Vision pipeline

    private let pipelineActor: VisionPipelineActor
    private let imuService: IMUService
    private let sessionLogger: RawSessionLogger = RawSessionLogger()

    private var currentIntrinsics: CameraIntrinsics = .zero

    // MARK: - Frame rate monitoring

    private var lastFrameTimestamp: CFTimeInterval?
    private var emaFrameInterval: Double = 1.0 / 240.0
    private let emaAlpha: Double = 0.05

    // Simple flag to drop frames when pipeline is busy
    private var isProcessingFrame: Bool = false

    // MARK: - Thermal

    private var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState {
        didSet {
            unsafeThermal = (thermalState == .serious || thermalState == .critical)
            Task {
                await pipelineActor.updateThermalState(thermalState)
            }
        }
    }

    // MARK: - Init

    init(config: BallLockConfig, imuService: IMUService = .shared) {
        self.session = AVCaptureSession()
        self.videoOutput = AVCaptureVideoDataOutput()
        self.captureQueue = DispatchQueue(
            label: "com.launchlab.camera.capture",
            qos: .userInteractive
        )
        self.ballLockConfig = config
        self.pipelineActor = VisionPipelineActor(config: config)
        self.imuService = imuService
        super.init()

        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        configureSession()
        startMonitoringThermal()
        imuService.start()
    }

    override convenience init() {
        let config = BallLockConfig()
        self.init(config: config, imuService: .shared)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public control (RootView expects these)

    func start() {
        startSession()
    }

    func stop() {
        stopSession()
    }

    func startSession() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
        imuService.stop()
    }

    func checkAuth() async {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run {
            self.authorizationStatus = current
        }

        guard current == .notDetermined else { return }

        let granted: Bool = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }

        let newStatus: AVAuthorizationStatus = granted ? .authorized : .denied
        await MainActor.run {
            self.authorizationStatus = newStatus
            if newStatus == .authorized {
                self.startSession()
            }
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        // Device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back) else {
            session.commitConfiguration()
            return
        }
        videoDevice = device

        // Input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        // Output
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()

        updateIntrinsics()
    }

    private func updateIntrinsics() {
        guard let device = videoDevice else {
            currentIntrinsics = .zero
            return
        }

        let format = device.activeFormat
        let desc = format.formatDescription
        let dims = CMVideoFormatDescriptionGetDimensions(desc)

        let w = Float(dims.width)
        let h = Float(dims.height)

        // Simple pinhole approximation; real intrinsics can be wired in later.
        let fx = w
        let fy = h
        let cx = w * 0.5
        let cy = h * 0.5

        currentIntrinsics = CameraIntrinsics(
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy
        )
    }

    // MARK: - Thermal monitoring

    private func startMonitoringThermal() {
        let info = ProcessInfo.processInfo
        thermalState = info.thermalState

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateDidChange(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: info
        )
    }

    @objc
    private func handleThermalStateDidChange(_ notification: Notification) {
        thermalState = ProcessInfo.processInfo.thermalState
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drop frame if previous one is still being processed
        if isProcessingFrame {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = pts.seconds

        // Frame rate monitoring via EMA
        let now = pts.seconds
        var unsafeFR = unsafeFrameRate
        if let last = lastFrameTimestamp {
            let dt = max(1e-6, now - last)
            emaFrameInterval = emaAlpha * dt + (1.0 - emaAlpha) * emaFrameInterval
            let fps = 1.0 / emaFrameInterval
            unsafeFR = fps < 200.0
            DispatchQueue.main.async {
                self.unsafeFrameRate = unsafeFR
            }
        }
        lastFrameTimestamp = now

        // Lighting heuristic on Y-plane
        let meanLuma = estimateMeanLuma(pixelBuffer: pixelBuffer)
        let unsafeLight = meanLuma < 0.08 || meanLuma > 0.95
        DispatchQueue.main.async {
            self.unsafeLighting = unsafeLight
        }

        let imuSnapshot = imuService.currentState
        let intrSnapshot = currentIntrinsics

        let isoSnapshot: Float
        let exposureDurationSnapshot: Double
        if let device = videoDevice {
            isoSnapshot = Float(device.iso)
            exposureDurationSnapshot = device.exposureDuration.seconds
        } else {
            isoSnapshot = 0
            exposureDurationSnapshot = 0
        }

        let unsafeLightingSnapshot = unsafeLight
        let unsafeFrameRateSnapshot = unsafeFR
        let unsafeThermalSnapshot = unsafeThermal

        isProcessingFrame = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let frame = await self.pipelineActor.processFrame(
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                intrinsics: intrSnapshot,
                imu: imuSnapshot
            )

            guard let frame = frame else {
                self.captureQueue.async {
                    self.isProcessingFrame = false
                }
                return
            }

            self.sessionLogger.handleFrame(
                frame: frame,
                imu: imuSnapshot,
                intrinsics: intrSnapshot,
                exposureISO: isoSnapshot,
                exposureDuration: exposureDurationSnapshot,
                unsafeLighting: unsafeLightingSnapshot,
                unsafeFrameRate: unsafeFrameRateSnapshot,
                unsafeThermal: unsafeThermalSnapshot
            )

            await MainActor.run {
                self.latestFrame = frame
            }

            self.captureQueue.async {
                self.isProcessingFrame = false
            }
        }
    }

    // MARK: - Lighting estimation

    private func estimateMeanLuma(pixelBuffer: CVPixelBuffer) -> Float {
        let planeIndex = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)

        guard width > 0, height > 0 else { return 0.5 }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex) else {
            return 0.5
        }

        let stepX = max(1, width / 32)
        let stepY = max(1, height / 32)

        var sum: Int = 0
        var count: Int = 0

        for y in stride(from: 0, to: height, by: stepY) {
            let rowPtr = base.advanced(by: y * rowBytes)
            let buffer = rowPtr.bindMemory(to: UInt8.self, capacity: width)
            for x in stride(from: 0, to: width, by: stepX) {
                sum += Int(buffer[x])
                count += 1
            }
        }

        if count == 0 { return 0.5 }
        let mean8 = Float(sum) / Float(count)
        return mean8 / 255.0
    }
}
