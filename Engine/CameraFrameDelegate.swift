//
//  CameraFrameDelegate.swift
//  LaunchLab
//

import CoreVideo
import CoreMedia

protocol CameraFrameDelegate: AnyObject {
    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime)
}
