//
//  PresenceAuthorityGate.swift
//  LaunchLab
//
//  Presence Authority (V1.3)
//
//  Determines whether a REAL BALL is present.
//
//  Order of evaluation:
//  1. Dynamic presence (FAST9 + jitter)
//  2. Static motion presence (low-speed stability)
//  3. Spatial presence (pixel occupancy)
//
//  Observation-only. No authority.
//

import Foundation
import CoreGraphics

enum PresenceDecision: Equatable {
    case present
    case absent(reason: String)
}

struct PresenceAuthorityInput: Equatable {
    let timestampSec: Double
    let ballLockConfidence: Float
    let center: CGPoint?
    let speedPxPerSec: Double
    let spatialMask: Set<Int>?
}

final class PresenceAuthorityGate {

    // MARK: - Dynamic presence (existing behavior)

    private let minConfidence: Float = 120
    private let maxJitterPx: Double = 4.0
    private let minStableFrames: Int = 6
    private let graceFrames: Int = 6

    private var recentCenters: [CGPoint] = []
    private var graceRemaining: Int = 6

    // MARK: - Static + Spatial

    private let staticAccumulator = StaticPresenceAccumulator()
    private let spatialObserver = SpatialPresenceObserver()

    // MARK: - Reset

    func reset() {
        recentCenters.removeAll()
        graceRemaining = graceFrames
        staticAccumulator.reset()
        spatialObserver.reset()
    }

    // MARK: - Update

    func update(_ input: PresenceAuthorityInput) -> PresenceDecision {

        // --------------------------------------------------
        // 1. Dynamic FAST9 presence
        // --------------------------------------------------

        if input.ballLockConfidence >= minConfidence,
           let center = input.center {

            recentCenters.append(center)
            if recentCenters.count > minStableFrames {
                recentCenters.removeFirst(recentCenters.count - minStableFrames)
            }

            if recentCenters.count < minStableFrames {
                graceRemaining -= 1
                return graceRemaining >= 0
                    ? .absent(reason: "warming_up")
                    : .absent(reason: "insufficient_stability")
            }

            let avg = averagePoint(recentCenters)
            let maxDist = recentCenters
                .map { hypot(Double($0.x - avg.x), Double($0.y - avg.y)) }
                .max() ?? 0

            if maxDist <= maxJitterPx {
                staticAccumulator.reset()
                spatialObserver.reset()

                Log.info(.shot, "PHASE presence_dynamic")
                return .present
            }
        }

        // --------------------------------------------------
        // 2. Static motion presence (low-speed)
        // --------------------------------------------------

        let staticDecision = staticAccumulator.observe(
            center: input.center,
            speedPxPerSec: input.speedPxPerSec,
            presenceConfidence: input.ballLockConfidence
        )

        if case .stable(let jitter, let frames) = staticDecision {
            spatialObserver.reset()

            Log.info(
                .shot,
                "PHASE presence_static_motion jitter=\(String(format: "%.2f", jitter)) frames=\(frames)"
            )
            return .present
        }

        // --------------------------------------------------
        // 3. Spatial presence (pixel occupancy)
        // --------------------------------------------------

        let spatialDecision = spatialObserver.observe(
            mask: input.spatialMask,
            confidence: input.ballLockConfidence
        )

        if case .present(let stability, let frames) = spatialDecision {
            Log.info(
                .shot,
                "PHASE presence_spatial stability=\(String(format: "%.2f", stability)) frames=\(frames)"
            )
            return .present
        }

        return .absent(reason: "no_presence")
    }

    // MARK: - Helpers

    private func averagePoint(_ pts: [CGPoint]) -> CGPoint {
        let sum = pts.reduce(CGPoint.zero) { acc, p in
            CGPoint(x: acc.x + p.x, y: acc.y + p.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(pts.count),
            y: sum.y / CGFloat(pts.count)
        )
    }
}
