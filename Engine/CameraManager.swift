// File: Camera/CameraManager.swift
// CameraManager = MainActor UI state + VisionPipeline coordinator.

import Foundation
import AVFoundation
import CoreVideo
import SwiftUI

@MainActor
public final class CameraManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var latestFrame: VisionFrameData?
    @Published public private(set) var intrinsics: CameraIntrinsics = .zero
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - BallLock Config (shared with VisionPipeline + SwiftUI)

    /// Runtime‑tunable BallLock configuration.
    /// Internal is fine — all code lives in the same module.
    let ballLockConfig = BallLockConfig()

    // MARK: - Internals

    /// The real capture engine (nonisolated).
    private let controller = CaptureController()

    /// Vision pipeline (runs on the main actor via Task).
    private let pipeline: VisionPipeline

    // MARK: - Init

    public init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        pipeline = VisionPipeline(ballLockConfig: ballLockConfig)
        bindControllerCallbacks()
    }

    // MARK: - Bind callbacks

    private func bindControllerCallbacks() {

        controller.onIntrinsicsReady = { [weak self] intr in
            Task { @MainActor in
                self?.intrinsics = intr
            }
        }

        controller.onFrame = { [weak self] buffer, timestamp in
            Task { @MainActor in
                guard let self else { return }

                let frame = self.pipeline.processFrame(
                    pixelBuffer: buffer,
                    timestamp: timestamp,
                    intrinsics: self.intrinsics
                )

                self.latestFrame = frame
            }
        }
    }

    // MARK: - Authorization

    public func checkAuth() async {
        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }
    }

    // MARK: - Public session access for PreviewView

    public var cameraSession: AVCaptureSession {
        controller.session
    }

    // MARK: - Start / Stop

    public func start() {
        guard authorizationStatus == .authorized else { return }
        controller.configureAndStart()
    }

    public func stop() {
        controller.stop()
    }
}
