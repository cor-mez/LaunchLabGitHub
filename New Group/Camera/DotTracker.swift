//
//  DotTracker.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

/// Stateless: returns the input dots directly.
/// No temporal associations, no optical flow.
final class DotTracker: @unchecked Sendable {

    init() {}

    func process(
        detections: [VisionDot],
        timestamp: Double
    ) -> [VisionDot] {
        return detections
    }
}
