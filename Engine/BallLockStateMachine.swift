// File: Vision/BallLock/BallLockStateMachine.swift
// BallLockStateMachine — high-velocity state machine with hysteresis + ROI shrinking.

import Foundation
import CoreGraphics

enum BallLockState: Int {
    case searching = 0
    case candidate = 1
    case locked    = 2
    case cooldown  = 3
}

struct BallLockOutput {
    let state: BallLockState
    let stateCode: Int
    let roiCenter: CGPoint?
    let roiRadius: CGFloat?
    let quality: CGFloat
    let isLocked: Bool
}

final class BallLockStateMachine {

    // Constant thresholds (from research)
    private let suddenDropThreshold: CGFloat = 0.20
    private let minLockedRadius: CGFloat = 40.0

    // State
    private(set) var state: BallLockState = .searching
    private var goodFrameCount: Int = 0
    private var badFrameCount: Int = 0
    private var currentCenter: CGPoint?
    private var currentRadius: CGFloat?

    func reset() {
        state = .searching
        goodFrameCount = 0
        badFrameCount = 0
        currentCenter = nil
        currentRadius = nil
    }

    /// Updates the lock state from the latest cluster plus runtime config.
    ///
    /// - Parameters:
    ///   - cluster: Latest ball cluster (if any) inside search ROI.
    ///   - dt: Frame delta time (seconds).
    ///   - frameIndex: Monotonic frame index.
    ///   - searchRoiCenter: Search ROI center in pixels.
    ///   - searchRoiRadius: Search ROI radius in pixels.
    ///   - qLock: Quality threshold to count as "good" for lock.
    ///   - qStay: Quality threshold to stay in candidate/locked.
    ///   - lockAfterN: Number of consecutive good frames to lock.
    ///   - unlockAfterM: Number of bad frames to unlock.
    ///   - alphaCenter: Centroid smoothing factor.
    ///   - roiRadiusFactor: Locked ROI radius factor (e.g. 2× cluster radius).
    ///   - loggingEnabled: If true, prints LOCK/UNLOCK transitions.
    func update(
        cluster: BallCluster?,
        dt: Double,
        frameIndex: Int,
        searchRoiCenter: CGPoint,
        searchRoiRadius: CGFloat,
        qLock: CGFloat,
        qStay: CGFloat,
        lockAfterN: Int,
        unlockAfterM: Int,
        alphaCenter: CGFloat,
        roiRadiusFactor: CGFloat,
        loggingEnabled: Bool
    ) -> BallLockOutput {
        _ = dt

        let previousState = state

        let quality: CGFloat = cluster?.qualityScore ?? 0
        let hasCluster = cluster != nil

        // Sudden quality collapse: go straight to cooldown from candidate/locked.
        if quality < suddenDropThreshold, (state == .locked || state == .candidate) {
            state = .cooldown
            goodFrameCount = 0
            badFrameCount = 1
        } else {
            switch state {
            case .searching:
                handleSearchingState(
                    hasCluster: hasCluster,
                    quality: quality,
                    qLock: qLock,
                    qStay: qStay
                )

            case .candidate:
                handleCandidateState(
                    hasCluster: hasCluster,
                    quality: quality,
                    qLock: qLock,
                    qStay: qStay,
                    lockAfterN: lockAfterN,
                    unlockAfterM: unlockAfterM
                )

            case .locked:
                handleLockedState(
                    hasCluster: hasCluster,
                    quality: quality,
                    qStay: qStay,
                    unlockAfterM: unlockAfterM
                )

            case .cooldown:
                handleCooldownState(unlockAfterM: unlockAfterM)
            }
        }

        // ROI center and radius updates for candidate/locked.
        if let cluster = cluster {
            switch state {
            case .candidate, .locked:
                updateCenter(using: cluster, alphaCenter: alphaCenter)
                updateRadiusIfNeeded(
                    using: cluster,
                    searchRoiRadius: searchRoiRadius,
                    roiRadiusFactor: roiRadiusFactor
                )
            default:
                break
            }
        }

        let outputCenter = currentCenter ?? searchRoiCenter
        let outputRadius = currentRadius ?? searchRoiRadius

        let output = BallLockOutput(
            state: state,
            stateCode: state.rawValue,
            roiCenter: outputCenter,
            roiRadius: outputRadius,
            quality: quality,
            isLocked: state == .locked
        )

        // Lightweight transition logging (optional)
        if loggingEnabled, previousState != state {
            logTransition(
                from: previousState,
                to: state,
                quality: quality,
                frameIndex: frameIndex
            )
        }

        return output
    }

    // MARK: - Private state handlers

    private func handleSearchingState(
        hasCluster: Bool,
        quality: CGFloat,
        qLock: CGFloat,
        qStay: CGFloat
    ) {
        if hasCluster {
            if quality >= qLock {
                state = .candidate
                goodFrameCount = 1
                badFrameCount = 0
            } else if quality >= qStay {
                state = .candidate
                goodFrameCount = 0
                badFrameCount = 0
            } else {
                badFrameCount += 1
                goodFrameCount = 0
            }
        } else {
            badFrameCount += 1
            goodFrameCount = 0
        }
    }

    private func handleCandidateState(
        hasCluster: Bool,
        quality: CGFloat,
        qLock: CGFloat,
        qStay: CGFloat,
        lockAfterN: Int,
        unlockAfterM: Int
    ) {
        if hasCluster {
            if quality >= qLock {
                goodFrameCount += 1
                badFrameCount = 0
                if goodFrameCount >= lockAfterN {
                    state = .locked
                }
            } else if quality >= qStay {
                // Stay candidate, don't accumulate good frames for lock.
                badFrameCount = 0
                goodFrameCount = 0
            } else {
                badFrameCount += 1
                goodFrameCount = 0
                if badFrameCount >= unlockAfterM {
                    state = .searching
                    badFrameCount = 0
                }
            }
        } else {
            badFrameCount += 1
            goodFrameCount = 0
            if badFrameCount >= unlockAfterM {
                state = .searching
                badFrameCount = 0
            }
        }
    }

    private func handleLockedState(
        hasCluster: Bool,
        quality: CGFloat,
        qStay: CGFloat,
        unlockAfterM: Int
    ) {
        if hasCluster {
            if quality >= qStay {
                badFrameCount = 0
            } else {
                badFrameCount += 1
                if badFrameCount >= unlockAfterM {
                    state = .cooldown
                    goodFrameCount = 0
                    badFrameCount = 1
                }
            }
        } else {
            badFrameCount += 1
            if badFrameCount >= unlockAfterM {
                state = .cooldown
                goodFrameCount = 0
                badFrameCount = 1
            }
        }
    }

    private func handleCooldownState(unlockAfterM: Int) {
        badFrameCount += 1
        goodFrameCount = 0
        if badFrameCount >= unlockAfterM {
            state = .searching
            badFrameCount = 0
        }
    }

    // MARK: - ROI updates

    private func updateCenter(using cluster: BallCluster, alphaCenter: CGFloat) {
        let rawCenter = cluster.centroid
        if let previousCenter = currentCenter {
            let invAlpha = 1.0 - alphaCenter
            currentCenter = CGPoint(
                x: previousCenter.x * invAlpha + rawCenter.x * alphaCenter,
                y: previousCenter.y * invAlpha + rawCenter.y * alphaCenter
            )
        } else {
            currentCenter = rawCenter
        }
    }

    private func updateRadiusIfNeeded(
        using cluster: BallCluster,
        searchRoiRadius: CGFloat,
        roiRadiusFactor: CGFloat
    ) {
        guard state == .locked else {
            // In candidate state we keep the search ROI radius as the outer bound.
            if currentRadius == nil {
                currentRadius = searchRoiRadius
            }
            return
        }

        let baseRadius = clamp(
            roiRadiusFactor * cluster.radiusPx,
            minLockedRadius,
            searchRoiRadius
        )

        if let oldRadius = currentRadius {
            // Shrink-only policy in locked state.
            currentRadius = oldRadius < baseRadius ? oldRadius : baseRadius
        } else {
            currentRadius = baseRadius
        }
    }

    private func clamp(
        _ value: CGFloat,
        _ minValue: CGFloat,
        _ maxValue: CGFloat
    ) -> CGFloat {
        if value < minValue { return minValue }
        if value > maxValue { return maxValue }
        return value
    }

    // MARK: - Logging

    private func logTransition(
        from old: BallLockState,
        to new: BallLockState,
        quality: CGFloat,
        frameIndex: Int
    ) {
        // Keep log strings short and only on transitions.
        if new == .locked {
            print("BallLock: LOCKED at frame \(frameIndex) (Q=\(String(format: "%.2f", quality)))")
        } else if old == .locked {
            print("BallLock: UNLOCK → \(new) at frame \(frameIndex)")
        } else {
            print("BallLock: \(old) → \(new) at frame \(frameIndex)")
        }
    }
}
