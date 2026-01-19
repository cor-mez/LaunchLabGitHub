//
//  RefractoryGate.swift
//  LaunchLab
//
//  Hard non-reentrant one-shot suppression gate.
//  Guarantees: ONE physical impulse → ONE detection.
//  Time-based lock + quiet-based release.
//  No physics heuristics. No decay modeling.
//

import Foundation

final class RefractoryGate {

    // -----------------------------------------------------------------
    // MARK: - Configuration (LOCKED FOR V1)
    // -----------------------------------------------------------------

    /// Absolute dead-time after accepting an impulse
    private let refractoryDuration: TimeInterval = 0.600   // 600 ms

    /// Required quiet frames AFTER refractory window to re-arm
    private let minQuietFrames: Int = 12

    // -----------------------------------------------------------------
    // MARK: - State
    // -----------------------------------------------------------------

    private enum State {
        case ready
        case locked(until: TimeInterval)
    }

    private var state: State = .ready
    private var quietFrameCount: Int = 0

    /// Observability only
    private var lastAcceptedTimestamp: TimeInterval?

    // -----------------------------------------------------------------
    // MARK: - Reset
    // -----------------------------------------------------------------

    func reset(reason: String? = nil) {
        state = .ready
        quietFrameCount = 0

        if let reason {
            Log.info(.shot, "refractory_reset reason=\(reason)")
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Update (per-frame)
    // -----------------------------------------------------------------

    /// Call once per frame with scene quiet signal.
    /// Scene quiet MUST mean: no centroid motion, no RS impulse, no gross motion.
    func update(
        timestamp: TimeInterval,
        sceneIsQuiet: Bool
    ) {
        switch state {

        case .ready:
            // Nothing to do; we only count quiet frames while locked
            break

        case .locked(let until):

            // Still inside hard dead-time window
            if timestamp < until {
                quietFrameCount = 0
                return
            }

            // Past dead-time window: require sustained quiet to re-arm
            if sceneIsQuiet {
                quietFrameCount += 1

                if quietFrameCount >= minQuietFrames {
                    Log.info(
                        .shot,
                        String(
                            format: "refractory_released t=%.3f quietFrames=%d",
                            timestamp,
                            quietFrameCount
                        )
                    )
                    reset(reason: "quiet_sustained")
                }
            } else {
                quietFrameCount = 0
            }
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Authority
    // -----------------------------------------------------------------

    /// Returns TRUE exactly once per physical strike.
    /// All subsequent calls return false until refractory is released.
    func tryAcceptImpulse(timestamp: TimeInterval) -> Bool {

        switch state {

        case .ready:
            state = .locked(until: timestamp + refractoryDuration)
            quietFrameCount = 0

            let deltaString: String = {
                guard let last = lastAcceptedTimestamp else { return "n/a" }
                return String(format: "%.3f", timestamp - last)
            }()

            lastAcceptedTimestamp = timestamp

            Log.info(
                .shot,
                String(
                    format: "refractory_locked t=%.3f until=%.3f Δt=%@",
                    timestamp,
                    timestamp + refractoryDuration,
                    deltaString
                )
            )
            return true

        case .locked:
            return false
        }
    }

    // -----------------------------------------------------------------
    // MARK: - Introspection (DEBUG ONLY)
    // -----------------------------------------------------------------

    var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    var lockedUntil: TimeInterval? {
        if case .locked(let until) = state { return until }
        return nil
    }
}
