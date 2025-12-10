//
//  DotDetectorConfig.swift
//  LaunchLab
//

import Foundation

public enum BlueEnhancementMode: Int, Codable {
    case off        // Y-path only
    case boxBlur    // Adaptive Blue → BoxBlur → FAST9
    case bilateral  // Adaptive Blue → Bilateral → FAST9
}

public struct DotDetectorConfig {

    // FAST9 thresholds
    public var fast9Threshold: Int
    public var vImageThreshold: Float

    // Gain / preprocessing
    public var preFilterGain: Float
    public var blueChromaGain: Float

    // Channel selection + Blue enhancement mode
    public var useBlueChannel: Bool
    public var blueEnhancement: BlueEnhancementMode

    // Super-resolution
    public var useSuperResolution: Bool
    public var srScaleOverride: Float?

    // Debug flags
    public var debugShowYROI: Bool
    public var debugShowBlueROI: Bool
    public var debugShowNormalizedBlue: Bool

    public init(
        fast9Threshold: Int = 14,
        vImageThreshold: Float = 30.0,
        preFilterGain: Float = 1.35,
        blueChromaGain: Float = 4.0,
        useBlueChannel: Bool = true,
        blueEnhancement: BlueEnhancementMode = .boxBlur,
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
        self.blueEnhancement = blueEnhancement
        self.useSuperResolution = useSuperResolution
        self.srScaleOverride = srScaleOverride
        self.debugShowYROI = debugShowYROI
        self.debugShowBlueROI = debugShowBlueROI
        self.debugShowNormalizedBlue = debugShowNormalizedBlue
    }
}
