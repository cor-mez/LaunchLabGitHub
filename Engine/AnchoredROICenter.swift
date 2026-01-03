//
//  AnchoredROICenter.swift
//  LaunchLab
//
//  Anchors the ROI center to the detected ball position
//  to suppress background-relative jitter.
//
//  This is NOT tracking.
//  It is a reference-frame stabilizer.
//

import CoreGraphics

final class AnchoredROICenter {

    // MARK: - Parameters

    /// Max pixels the ROI center may drift per frame
    private let maxDriftPxPerFrame: CGFloat = 3.0

    // MARK: - State

    private var anchoredCenter: CGPoint?

    // MARK: - Reset

    func reset() {
        anchoredCenter = nil
    }

    // MARK: - Update

    func update(with detectedCenter: CGPoint) -> CGPoint {

        guard let current = anchoredCenter else {
            anchoredCenter = detectedCenter
            return detectedCenter
        }

        let dx = detectedCenter.x - current.x
        let dy = detectedCenter.y - current.y

        let dist = hypot(dx, dy)

        if dist <= maxDriftPxPerFrame {
            anchoredCenter = detectedCenter
            return detectedCenter
        }

        // Clamp movement
        let scale = maxDriftPxPerFrame / dist

        let clamped = CGPoint(
            x: current.x + dx * scale,
            y: current.y + dy * scale
        )

        anchoredCenter = clamped
        return clamped
    }
}
