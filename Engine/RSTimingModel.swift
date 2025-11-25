//
//  RSTimingModel.swift
//  LaunchLab
//

import Foundation
import simd

public struct RSTimingModel {

    public let imageHeight: Int
    public let readoutTime: Float
    public let exposureTime: Float
    private let timePerRow: Float

    // Static factory (per your directive)
    public static func make(imageHeight: Int) -> RSTimingModel {
        // Default values for iPhone 240 fps
        let readout: Float = 1.0 / 5000.0
        let exposure: Float = 1.0 / 10000.0
        let h = max(imageHeight, 1)
        return RSTimingModel(
            imageHeight: imageHeight,
            readoutTime: readout,
            exposureTime: exposure,
            timePerRow: readout / Float(h)
        )
    }

    private init(
        imageHeight: Int,
        readoutTime: Float,
        exposureTime: Float,
        timePerRow: Float
    ) {
        self.imageHeight = imageHeight
        self.readoutTime = readoutTime
        self.exposureTime = exposureTime
        self.timePerRow = timePerRow
    }

    public func timestampForRow(_ row: Int) -> Float {
        let clamped = max(0, min(imageHeight - 1, row))
        return Float(clamped) * timePerRow + exposureTime * 0.5
    }
}
