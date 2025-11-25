//
//  CalibrationControllerProtocol.swift
//  LaunchLab
//

import Foundation
import CoreVideo

/// Anything that wants to receive raw frames in calibration mode
/// must implement this protocol.
/// CameraManager calls `processFrame` directly from capture queue.
public protocol CalibrationControllerProtocol: AnyObject {
    func processFrame(pixelBuffer: CVPixelBuffer, timestamp: Float)
}
