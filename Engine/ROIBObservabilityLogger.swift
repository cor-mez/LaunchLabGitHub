//
//  ROIBObservabilityLogger.swift
//  LaunchLab
//
//  Observational logging for ROI-B effectiveness.
//

import CoreGraphics

final class ROIBObservabilityLogger {

    private var frames: Int = 0
    private var maxSpeed: Double = 0
    private var maxEscape: Double = 0

    func reset() {
        frames = 0
        maxSpeed = 0
        maxEscape = 0
    }

    func observe(center: CGPoint, speedPxPerSec: Double) {
        frames += 1
        maxSpeed = max(maxSpeed, speedPxPerSec)
    }

    func observeEscape(from origin: CGPoint, to center: CGPoint) {
        let dx = center.x - origin.x
        let dy = center.y - origin.y
        let dist = hypot(dx, dy)
        maxEscape = max(maxEscape, dist)
    }

    func emitSummary() {
        Log.info(
            .shot,
            "[ROI-B] frames=\(frames) max_px_s=\(String(format: "%.1f", maxSpeed)) " +
            "max_escape=\(String(format: "%.1f", maxEscape))"
        )
    }
}
