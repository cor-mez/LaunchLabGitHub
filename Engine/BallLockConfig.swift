// File: Vision/BallLock/BallLockConfig.swift
// BallLockConfig -- runtime-tunable parameters for BallCluster + BallLock.

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
    
    /// Quality needed to accumulate "good" frames toward lock.
    @Published var qLock: Double = 0.55 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: qLock) }
    }
    
    /// Quality needed to stay in candidate/locked.
    @Published var qStay: Double = 0.40 {
        didSet { markNeedsResetForMajorChange(oldValue: oldValue, newValue: qStay) }
    }
    
    @Published var lockAfterN: Int = 5
    @Published var unlockAfterM: Int = 6
    
    // MARK: - Smoothing / ROI
    
    /// Centroid EMA factor -- lower = smoother (less jitter).
    /// Research corridor: ~0.15–0.20
    @Published var alphaCenter: Double = 0.20
    
    /// Locked ROI radius factor (× cluster radius).
    /// Research corridor: ~1.2–1.3
    @Published var roiRadiusFactor: Double = 1.25
    
    // MARK: - Quality Weights (CNT / SYM / RAD)
    
    /// Research defaults: 0.4 count, 0.4 symmetry, 0.2 radius.
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
// File: Engine/BallLockConfig.swift
// Add this at the bottom of the file:

extension BallLockConfig {
    /// Safe baseline configuration for UI, Pipeline, and Debug Panels
    static var `default`: BallLockConfig {
        let cfg = BallLockConfig()

        // Cluster size
        cfg.minCorners = 6
        cfg.maxCorners = 60
        cfg.minRadiusPx = 10
        cfg.maxRadiusPx = 200

        // Weights
        cfg.symmetryWeight = 0.4
        cfg.countWeight = 0.3
        cfg.radiusWeight = 0.3

        // Quality thresholds
        cfg.qLock = 0.55
        cfg.qStay = 0.45
        cfg.minQualityToEnterLock = 0.40

        // State machine
        cfg.lockAfterN = 3
        cfg.unlockAfterM = 3

        // ROI / smoothing
        cfg.alphaCenter = 0.25
        cfg.roiRadiusFactor = 0.90

        // Reset flag will be false by default
        return cfg
    }
}
