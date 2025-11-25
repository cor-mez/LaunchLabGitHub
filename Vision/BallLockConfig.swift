// File: Vision/BallLock/BallLockConfig.swift
// BallLockConfig — runtime-tunable parameters for BallCluster + BallLock.
// Uses only local Swift types; no changes to VisionTypes.swift.

import Foundation
import Combine

final class BallLockConfig: ObservableObject {

    // MARK: - Cluster

    @Published var minCorners: Int = 8 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: minCorners) }
    }

    @Published var maxCorners: Int = 28 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: maxCorners) }
    }

    @Published var minRadiusPx: Double = 10 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: minRadiusPx) }
    }

    @Published var maxRadiusPx: Double = 120 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: maxRadiusPx) }
    }

    /// Minimum quality required for a cluster to be *eligible* for locking.
    @Published var minQualityToEnterLock: Double = 0.55

    // MARK: - State Machine

    @Published var qLock: Double = 0.55 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: qLock) }
    }

    @Published var qStay: Double = 0.40 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: qStay) }
    }

    @Published var lockAfterN: Int = 5
    @Published var unlockAfterM: Int = 6

    // MARK: - Smoothing / ROI

    /// Centroid EMA factor — lower = smoother (less jitter).
    @Published var alphaCenter: Double = 0.20

    /// Locked ROI radius factor, relative to cluster radius.
    @Published var roiRadiusFactor: Double = 1.25

    // MARK: - Quality Weights

    /// Weights used in composite quality = wC * CNT + wS * SYM + wR * RAD (renormalized each frame).
    @Published var symmetryWeight: Double = 0.40
    @Published var countWeight: Double = 0.40
    @Published var radiusWeight: Double = 0.20

    // MARK: - Velocity Coherence (v1 exposed, default OFF)

    @Published var enableVelocityCoherence: Bool = false
    @Published var velocityAngleTolerance: Double = 20.0         // degrees
    @Published var velocityMagnitudeRatioTolerance: Double = 0.5 // ratio

    // MARK: - Debug Flags

    @Published var showBallLockDebug: Bool = true
    @Published var showBallLockBreadcrumb: Bool = true
    @Published var showBallLockTextHUD: Bool = true
    @Published var showBallLockLogging: Bool = false
    @Published var showClusterDots: Bool = true

    // MARK: - Reset signalling

    /// Flips when "major" parameters change so VisionPipeline can soft-reset BallLock.
    @Published private(set) var needsReset: Bool = false

    // MARK: - Public API

    /// Explicit reset request (from tuning HUD button).
    func requestReset() {
        needsReset.toggle()
    }

    // MARK: - Private helpers

    private func markNeedsResetForMajorChange<T: Equatable>(oldValue: T, newValue: T) {
        guard oldValue != newValue else { return }
        needsReset.toggle()
    }
}
