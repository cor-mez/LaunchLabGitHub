//
//  RawMotionLogger.swift
//  LaunchLab
//
//  Observation-only motion logging (V1)
//  NO decisions, NO thresholds, NO lifecycle coupling
//

import Foundation
import CoreGraphics

@MainActor
final class RawMotionLogger {

    private var lastCenter: CGPoint?
    private var lastTimestamp: Double?

    func reset() {
        lastCenter = nil
        lastTimestamp = nil
    }

    func log(
        timestampSec: Double,
        center: CGPoint?,
        clusterCount: Int
    ) {
        guard let center,
              let lastCenter,
              let lastTimestamp else {
            self.lastCenter = center
            self.lastTimestamp = timestampSec
            return
        }

        let dx = center.x - lastCenter.x
        let dy = center.y - lastCenter.y
        let dt = timestampSec - lastTimestamp
        let pxPerSec = dt > 0 ? hypot(dx, dy) / dt : 0

        Log.info(
            .shot,
            String(
                format: "motion t=%.3f locked=true dx=%.2f dy=%.2f px_s=%.2f conf=%d",
                timestampSec, dx, dy, pxPerSec, clusterCount
            )
        )

        self.lastCenter = center
        self.lastTimestamp = timestampSec
    }

    func logUnlocked(timestampSec: Double) {
        Log.info(
            .shot,
            String(format: "motion t=%.3f locked=false", timestampSec)
        )
        reset()
    }
}
