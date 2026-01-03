//
//  CameraStabilityController.swift
//  LaunchLab
//
//  Locks AE / AF / AWB exactly once after alignment.
//  Never toggles during detection.
//  Prevents optical regime shifts (luma flashes, chroma jumps).
//

import AVFoundation

@MainActor
final class CameraStabilityController {

    private weak var device: AVCaptureDevice?
    private(set) var isLocked: Bool = false

    init(device: AVCaptureDevice) {
        self.device = device
    }

    /// Call ONCE after user alignment is complete.
    /// Safe to call multiple times — only locks once.
    func lockIfNeeded() {
        guard !isLocked else { return }
        guard let device else { return }

        guard device.isExposureModeSupported(.locked),
              device.isFocusModeSupported(.locked),
              device.isWhiteBalanceModeSupported(.locked)
        else {
            Log.info(.shot, "[CAMERA] lock unsupported on device")
            return
        }

        do {
            try device.lockForConfiguration()

            device.exposureMode = .locked
            device.focusMode = .locked
            device.whiteBalanceMode = .locked

            device.unlockForConfiguration()
            isLocked = true

            Log.info(.shot, "[CAMERA] AE/AF/AWB locked")

        } catch {
            Log.info(.shot, "[CAMERA] lock failed: \(error)")
        }
    }

    /// Explicit teardown only (leaving detection / app background).
    func unlock() {
        guard isLocked, let device else { return }

        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.unlockForConfiguration()
            isLocked = false

            Log.info(.shot, "[CAMERA] AE/AF/AWB unlocked")

        } catch {
            Log.info(.shot, "[CAMERA] unlock failed: \(error)")
        }
    }
}
