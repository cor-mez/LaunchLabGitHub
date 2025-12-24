//
//  DotTestMode.swift
//

import Foundation
import CoreGraphics
import MetalKit

@MainActor
final class DotTestMode: ObservableObject {
    
    static let shared = DotTestMode()
    var previewEnabled: Bool = false

    private init() {}

    // -------------------------------------------------------------------------
    // MARK: - Backend Selection
    // -------------------------------------------------------------------------

    enum Backend: CaseIterable {
        case cpu
        case gpuY
        case gpuCb
        case gpuReadback
    }

    @Published var backend: Backend = .gpuY

    // -------------------------------------------------------------------------
    // MARK: - Debug Surface Selection
    // -------------------------------------------------------------------------

    enum DebugSurface: CaseIterable {
        case yRaw
        case yNorm
        case yEdge

        case cbRaw
        case cbNorm
        case cbEdge

        case fast9y
        case fast9cb

        case mismatchHeatmap
        case mixedCorners
    }

    @Published var debugSurface: DebugSurface = .mixedCorners

    // Heatmap visibility toggles
    @Published var showHeatmap: Bool = false
    @Published var showVectors: Bool = true

    // -------------------------------------------------------------------------
    // MARK: - Tuning Parameters
    // -------------------------------------------------------------------------

    // FAST9 thresholds & scoring
    @Published var fast9ThresholdY: Int = 35
    @Published var fast9ThresholdCb: Int = 6
    @Published var fast9ScoreMinY: Int = 14
    @Published var fast9ScoreMinCb: Int = 12
    @Published var fast9NmsRadius: Int = 1
    @Published var maxCorners: Int = 500

    // ROI controls
    @Published var roiScale: CGFloat = 1.0
    @Published var roiOffsetX: CGFloat = 0.0
    @Published var roiOffsetY: CGFloat = 0.0

    // Super-resolution scale
    @Published var srScale: Float = 1.5

    // -------------------------------------------------------------------------
    // MARK: - Telemetry Storage (Consumed by UI + Overlay)
    // -------------------------------------------------------------------------

    @Published var cpuCorners: [CGPoint] = []
    @Published var gpuCorners: [CGPoint] = []
    @Published var matchCorners: [CGPoint] = []
    @Published var cpuOnlyCorners: [CGPoint] = []
    @Published var gpuOnlyCorners: [CGPoint] = []

    // CPU↔GPU mismatch vectors (tuple of raw points)
    @Published var mismatchVectors: [(CGPoint, CGPoint)] = []

    // Counts
    @Published var cpuCornerCount: Int = 0
    @Published var gpuCornerCount: Int = 0

    // Score metrics
    @Published var avgGpuScore: Float = 0
    @Published var minGpuScore: Float = 0
    @Published var maxGpuScore: Float = 0

    // Spatial error telemetry
    @Published var avgSpatialError: CGFloat = 0
    @Published var maxSpatialError: CGFloat = 0

    // NMS cluster size
    @Published var nmsClusterSize: Int = 0

    // Convenience
    var matchCount: Int { matchCorners.count }

    // Heatmap texture
    @Published var mismatchHeatmapTexture: MTLTexture?

    // -------------------------------------------------------------------------
    // MARK: - Detection Gating (Stability)
    // -------------------------------------------------------------------------

    @Published var isArmedForDetection: Bool = false
    @Published var founderTestModeEnabled: Bool = false
    @Published var warmupFrameCount: Int = 0
    let warmupFramesNeeded: Int = 5

    // -------------------------------------------------------------------------
    // MARK: - Telemetry Update API (Atomic + MainActor Safe)
    // -------------------------------------------------------------------------

    func updateTelemetry(
        cpu: [CGPoint],
        gpu: [CGPoint],
        matches: [CGPoint],
        cpuOnly: [CGPoint],
        gpuOnly: [CGPoint],
        avgScore: Float,
        minScore: Float,
        maxScore: Float,
        clusterSize: Int,
        avgErr: CGFloat,
        maxErr: CGFloat,
        vectors: [(CGPoint, CGPoint)]
    ) {
        cpuCorners = cpu
        gpuCorners = gpu
        matchCorners = matches
        cpuOnlyCorners = cpuOnly
        gpuOnlyCorners = gpuOnly
        mismatchVectors = vectors

        cpuCornerCount = cpu.count
        gpuCornerCount = gpu.count

        avgGpuScore = avgScore
        minGpuScore = minScore
        maxGpuScore = maxScore

        nmsClusterSize = clusterSize
        avgSpatialError = avgErr
        maxSpatialError = maxErr
    }

    // -------------------------------------------------------------------------
    // MARK: - ROI Computation (Portrait-Correct)
    // -------------------------------------------------------------------------

    func applyROI(to base: CGRect, in full: CGSize) -> CGRect {

        guard full.width > 0, full.height > 0 else { return .zero }

        let w = base.width * roiScale
        let h = base.height * roiScale

        var x = base.origin.x + roiOffsetX
        var y = base.origin.y + roiOffsetY

        // Enforce boundaries
        if x < 0 { x = 0 }
        if y < 0 { y = 0 }
        if x + w > full.width  { x = full.width  - w }
        if y + h > full.height { y = full.height - h }

        return CGRect(x: x, y: y, width: max(w, 8), height: max(h, 8))
    }
}
