//
//  CameraFrameDelegate.swift
//

import CoreVideo

@MainActor
protocol CameraFrameDelegate: AnyObject {
    /// Called on the MainActor for every captured frame.
    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer)
}
