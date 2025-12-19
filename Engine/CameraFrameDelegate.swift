//
//  CameraFrameDelegate.swift
//

import CoreMedia
import CoreVideo

@MainActor
protocol CameraFrameDelegate: AnyObject {
    /// Called on the MainActor for every captured frame.
    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime)
}
