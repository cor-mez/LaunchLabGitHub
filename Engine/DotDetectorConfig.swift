// File: Engine/DotDetectorConfig.swift
// LaunchLab — Unified Dot Detector Configuration
//
// This struct contains EVERY tunable parameter used by:
//   • Y-path preprocessing
//   • Blue-channel normalization
//   • Super-resolution
//   • FAST9 corner detection
//   • DotTestMode runtime overrides
//
// All fields are public and internal-accessible across helper modules.

import Foundation

public struct DotDetectorConfig {

    // =======================================================
    // MARK: - FAST9 Thresholds
    // =======================================================

    /// FAST9 intensity threshold (typically 8–20)
    public var fast9Threshold: Int

    /// Local contrast pre-check threshold (before full FAST9)
    public var vImageThreshold: Float

    // =======================================================
    // MARK: - Gain / Preprocessing
    // =======================================================

    /// Y-path brightness amplification
    public var preFilterGain: Float

    /// Blue-path chroma amplification
    public var blueChromaGain: Float

    // =======================================================
    // MARK: - Channel Selection
    // =======================================================

    /// Use Blue-first FAST9 path
    public var useBlueChannel: Bool

    /// Enable Super-Resolution (SR-first)
    public var useSuperResolution: Bool

    // =======================================================
    // MARK: - SR Scaling
    // =======================================================

    /// Optional SR override: {1.0, 1.5, 2.0, 3.0}
    /// If nil → auto-selected based on ROI size
    public var srScaleOverride: Float?

    // =======================================================
    // MARK: - Debug / Developer UI Flags
    // =======================================================

    public var debugShowYROI: Bool
    public var debugShowBlueROI: Bool
    public var debugShowNormalizedBlue: Bool

    // =======================================================
    // MARK: - Init
    // =======================================================

    public init(
        fast9Threshold: Int = 14,
        vImageThreshold: Float = 30.0,
        preFilterGain: Float = 1.35,
        blueChromaGain: Float = 4.0,
        useBlueChannel: Bool = true,
        useSuperResolution: Bool = true,
        srScaleOverride: Float? = nil,
        debugShowYROI: Bool = false,
        debugShowBlueROI: Bool = false,
        debugShowNormalizedBlue: Bool = false
    ) {
        self.fast9Threshold = fast9Threshold
        self.vImageThreshold = vImageThreshold
        self.preFilterGain = preFilterGain
        self.blueChromaGain = blueChromaGain
        self.useBlueChannel = useBlueChannel
        self.useSuperResolution = useSuperResolution
        self.srScaleOverride = srScaleOverride
        self.debugShowYROI = debugShowYROI
        self.debugShowBlueROI = debugShowBlueROI
        self.debugShowNormalizedBlue = debugShowNormalizedBlue
    }
}
