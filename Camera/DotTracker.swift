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
// DotTracker.swift (ADD THIS EXTENSION at bottom of file)
extension DotTracker {

    // Backwards-compatible wrapper so VisionPipeline compiles
    public func trackDots(
        _ detected: [VisionDot],
        width: Int,
        height: Int,
        timestamp: Double
    ) -> [VisionDot] {
        return track(detected, timestamp: timestamp)
    }

    // Pipe reset call to your existing reset or create one if missing
    public func reset() {
        // If DotTracker already has cleanup logic, call it here.
    }
}
