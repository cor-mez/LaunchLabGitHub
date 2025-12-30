//
//  BallSpeedTracker.swift
//  LaunchLab
//
//  Deterministic ball speed tracker (V1)
//
//  - Pure engine utility
//  - No smoothing
//  - No prediction
//  - No UI assumptions
//

import Foundation
import CoreGraphics

final class BallSpeedTracker {

    private struct Sample {
        let position: CGPoint
        let timestampSec: Double
    }

    private var samples: [Sample] = []

    // MARK: - Lifecycle

    func reset() {
        samples.removeAll()
    }

    func ingest(position: CGPoint, timestampSec: Double) {
        samples.append(Sample(position: position, timestampSec: timestampSec))
    }

    // MARK: - Instantaneous Motion

    /// Pixel velocity between the last two samples.
    /// Used ONLY for gating (shot detection).
    var lastInstantaneousPxPerSec: Double? {
        guard samples.count >= 2 else { return nil }

        let a = samples[samples.count - 2]
        let b = samples[samples.count - 1]

        let dt = b.timestampSec - a.timestampSec
        guard dt > 0 else { return nil }

        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let distPx = hypot(dx, dy)

        return distPx / dt
    }

    // MARK: - Final Speed Computation

    func compute(pixelsPerMeter: Double) -> BallSpeedSample? {
        guard samples.count >= 2 else { return nil }
        guard pixelsPerMeter > 0 else { return nil }

        let first = samples.first!
        let last  = samples.last!

        let dx = last.position.x - first.position.x
        let dy = last.position.y - first.position.y
        let distancePx = hypot(dx, dy)

        let dt = last.timestampSec - first.timestampSec
        guard dt > 0 else { return nil }

        let pxPerSec = distancePx / dt

        guard let mph = UnitConverter.pxPerSecToMPH(
            pxPerSec,
            pixelsPerMeter: pixelsPerMeter
        ) else { return nil }

        let confidence: BallSpeedConfidence = {
            switch samples.count {
            case 0..<4:   return .low
            case 4..<8:   return .medium
            default:      return .high
            }
        }()

        return BallSpeedSample(
            pxPerSec: pxPerSec,
            mph: mph,
            sampleCount: samples.count,
            spanSec: dt,
            confidence: confidence
        )
    }
}
