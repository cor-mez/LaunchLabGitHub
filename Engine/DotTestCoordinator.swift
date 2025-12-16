//
//  DotTestCoordinator.swift
//

import Foundation
import CoreVideo
import CoreGraphics
import Metal

@MainActor
final class DotTestCoordinator {
    
    static let shared = DotTestCoordinator()
    // MARK: - Throttling
    private var frameIndex: Int = 0
    private let detectionInterval: Int = 3   // adjustable: 3 or 5
    
    private let mode      = DotTestMode.shared
    private let detector  = MetalDetector.shared
    private let renderer  = MetalRenderer.shared
    private let ballLock = BallLockV0()
    
    private var lastROI: CGRect  = .zero
    private var lastFull: CGSize = .zero
    private var lastBallLockCount: Int = 0
    private var smoothedBallLockCount: Float = 0
    private var ballLockHoldFrames: Int = 0
    private let maxHoldFrames: Int = 5
    private let matchDist: CGFloat = 2.0
    private var heatmapCounter = 0
    private let heatmapThrottle = 4
    
    // MARK: - Markerless Discrimination Gates (MDG)
    private let mdg = MarkerlessDiscriminationGates()
    private var mdgBallLikeEvidence: Bool = false
    private var mdgRejectReason: String? = nil
    
    private init() {}
    
    private struct BallLockMemory {
        var lastCenter: CGPoint
        var lastRadius: CGFloat
        var age: Int
    }
    private var ballLockMemory: BallLockMemory?
    
    
    // MARK: - Simple Spatial NMS (CPU, deterministic)
    
    private func applyNMS(
        _ points: [CGPoint],
        radius: CGFloat
    ) -> [CGPoint] {
        
        guard !points.isEmpty else { return [] }
        
        let r2 = radius * radius
        var kept: [CGPoint] = []
        
        // Deterministic: preserves input order
        for p in points {
            var suppressed = false
            
            for k in kept {
                let dx = p.x - k.x
                let dy = p.y - k.y
                if (dx * dx + dy * dy) <= r2 {
                    suppressed = true
                    break
                }
            }
            
            if !suppressed {
                kept.append(p)
            }
        }
        
        return kept
    }
    // MARK: - Density Gate (CPU, deterministic)
    
    private func applyDensityGate(
        _ points: [CGPoint],
        radius: CGFloat,
        minNeighbors: Int
    ) -> [CGPoint] {
        
        guard !points.isEmpty else { return [] }
        
        let r2 = radius * radius
        
        return points.filter { p in
            var neighbors = 0
            
            for q in points {
                let dx = p.x - q.x
                let dy = p.y - q.y
                if dx*dx + dy*dy <= r2 {
                    neighbors += 1
                    if neighbors >= minNeighbors {
                        return true
                    }
                }
            }
            
            return false
        }
    }
    
    // MARK: - Frame Entry (from DotTestViewController)
    // -------------------------------------------------------------------------
    func processFrame(_ pb: CVPixelBuffer) {
        
        frameIndex += 1
        
        // Always allow preview to render (handled elsewhere)
        // Throttle heavy detection deterministically
        guard frameIndex % detectionInterval == 0 else {
            return
        }
        
        guard mode.isArmedForDetection else { return }
        
        mode.warmupFrameCount += 1
        if mode.warmupFrameCount < mode.warmupFramesNeeded {
            return
        }
        
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 32, h > 32 else { return }
        
        lastFull = CGSize(width: w, height: h)
        
        runDetection(on: pb)
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Core Detection Dispatch
    // -------------------------------------------------------------------------
    
    private func runDetection(on pb: CVPixelBuffer) {
        
        let fullW  = CVPixelBufferGetWidth(pb)
        let fullH  = CVPixelBufferGetHeight(pb)
        let fullSz = CGSize(width: fullW, height: fullH)
        
        // Base ROI: lower half of screen
        // ---------------------------------------------------------------------
        // HARD ROI CLAMP (TEST MODE)
        // ---------------------------------------------------------------------
        
        let roiSize: CGFloat = 80  // start here (try 160 or 96 later)
        
        let roi = CGRect(
            x: fullSz.width  * 0.5 - roiSize * 0.5,
            y: fullSz.height * 0.5 - roiSize * 0.5,
            width: roiSize,
            height: roiSize
        ).integral
        
        lastROI = roi
        guard roi.width >= 8, roi.height >= 8 else {
            return
        }
        if DebugProbe.isEnabled(.capture) {
            print("[ROI] hardClamp x=\(Int(roi.origin.x)) y=\(Int(roi.origin.y)) w=\(Int(roi.width)) h=\(Int(roi.height))")
        }
        lastROI  = roi
        lastFull = fullSz
        
        let sr = mode.srScale
        
        switch mode.backend {
            
        case .cpu:
            detectCPU(
                pb: pb,
                roi: roi,
                fullSize: fullSz
            )
            
        case .gpuY:
            detectGPU_Readback(
                pb: pb,
                roi: roi,
                sr: sr,
                fullSize: fullSz
            )
            
        case .gpuCb:
            detectGPU_Cb(
                pb: pb,
                roi: roi,
                sr: sr,
                fullSize: fullSz
            )
            
        case .gpuReadback:
            detectGPU_Readback(
                pb: pb,
                roi: roi,
                sr: sr,
                fullSize: fullSz
            )
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - CPU Detection
    // -------------------------------------------------------------------------
    
    private func detectCPU(pb: CVPixelBuffer,
                           roi: CGRect,
                           fullSize: CGSize)
    {
        let cornersCPU = cpuFAST9(pb: pb, roi: roi)
        
        mode.updateTelemetry(
            cpu: cornersCPU,
            gpu: [],
            matches: [],
            cpuOnly: cornersCPU,
            gpuOnly: [],
            avgScore: 0,
            minScore: 0,
            maxScore: 0,
            clusterSize: 0,
            avgErr: 0,
            maxErr: 0,
            vectors: []
        )
        
        if mode.showHeatmap {
            mode.mismatchHeatmapTexture =
            makeHeatmapThrottled(cpu: cornersCPU,
                                 gpu: [],
                                 roi: roi,
                                 fullSize: fullSize)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - GPU-Y Detection
    // -------------------------------------------------------------------------
    
    private func detectGPU_Y(pb: CVPixelBuffer,
                             roi: CGRect,
                             sr: Float,
                             fullSize: CGSize)
    {
        detector.fast9ThresholdY = mode.fast9ThresholdY
        detector.fast9ScoreMinY  = mode.fast9ScoreMinY
        detector.nmsRadius       = mode.fast9NmsRadius
        
        detector.prepareFrameY(pb,
                               roi: roi,
                               srScale: sr)
        
        let (cornersGPU, tele) = detector.gpuFast9CornersYEnhanced()
        let cornersCPU = cpuFAST9(pb: pb, roi: roi)
        
        let diff = compare(cpu: cornersCPU, gpu: cornersGPU)
        
        mode.updateTelemetry(
            cpu: cornersCPU,
            gpu: cornersGPU,
            matches: diff.matches,
            cpuOnly: diff.cpuOnly,
            gpuOnly: diff.gpuOnly,
            avgScore: tele.mean,
            minScore: tele.min,
            maxScore: tele.max,
            clusterSize: diff.matches.count,
            avgErr: diff.avgErr,
            maxErr: diff.maxErr,
            vectors: diff.vectors
        )
        
        if mode.showHeatmap {
            mode.mismatchHeatmapTexture =
            makeHeatmapThrottled(cpu: cornersCPU,
                                 gpu: cornersGPU,
                                 roi: roi,
                                 fullSize: fullSize)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - GPU-Cb Detection
    // -------------------------------------------------------------------------
    
    private func detectGPU_Cb(pb: CVPixelBuffer,
                              roi: CGRect,
                              sr: Float,
                              fullSize: CGSize)
    {
        detector.fast9ThresholdCb = mode.fast9ThresholdCb
        detector.fast9ScoreMinCb  = mode.fast9ScoreMinCb
        detector.nmsRadius        = mode.fast9NmsRadius
        
        detector.prepareFrameCb(pb,
                                roi: roi,
                                srScale: sr)
        
        let (cornersGPU, tele) = detector.gpuFast9CornersCbEnhanced()
        let cornersCPU = cpuFAST9(pb: pb, roi: roi)
        
        let diff = compare(cpu: cornersCPU, gpu: cornersGPU)
        
        mode.updateTelemetry(
            cpu: cornersCPU,
            gpu: cornersGPU,
            matches: diff.matches,
            cpuOnly: diff.cpuOnly,
            gpuOnly: diff.gpuOnly,
            avgScore: tele.mean,
            minScore: tele.min,
            maxScore: tele.max,
            clusterSize: diff.matches.count,
            avgErr: diff.avgErr,
            maxErr: diff.maxErr,
            vectors: diff.vectors
        )
        
        if mode.showHeatmap {
            mode.mismatchHeatmapTexture =
            makeHeatmapThrottled(cpu: cornersCPU,
                                 gpu: cornersGPU,
                                 roi: roi,
                                 fullSize: fullSize)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - CPU FAST9
    // -------------------------------------------------------------------------
    
    private func cpuFAST9(pb: CVPixelBuffer, roi: CGRect) -> [CGPoint] {
        
        let r = roi.integral
        let w = Int(r.width)
        let h = Int(r.height)
        
        guard w > 8, h > 8 else { return [] }
        
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else {
            return []
        }
        
        let bytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let src = base.assumingMemoryBound(to: UInt8.self)
        
        var buf = [UInt8](repeating: 0, count: w * h)
        
        let ox = Int(r.origin.x)
        let oy = Int(r.origin.y)
        
        for j in 0..<h {
            let sRow = src + (oy + j) * bytes + ox
            let dRow = j * w
            for i in 0..<w {
                buf[dRow + i] = sRow[i]
            }
        }
        
        let thr = mode.fast9ThresholdY
        
        let circle = [
            ( 0,-3),( 1,-3),( 2,-2),( 3,-1),
            ( 3, 0),( 3, 1),( 2, 2),( 1, 3),
            ( 0, 3),(-1, 3),(-2, 2),(-3, 1),
            (-3, 0),(-3,-1),(-2,-2),(-1,-3)
        ]
        
        var out: [CGPoint] = []
        
        for y in 3..<(h - 3) {
            for x in 3..<(w - 3) {
                let c = Int(buf[y * w + x])
                var support = 0
                
                for (dx, dy) in circle {
                    let xx = x + dx
                    let yy = y + dy
                    let v  = Int(buf[yy * w + xx])
                    if abs(v - c) > thr {
                        support += 1
                    }
                }
                
                if support >= 9 {
                    out.append(CGPoint(x: x, y: y))
                }
            }
        }
        
        return out
    }
    
    // -------------------------------------------------------------------------
    // MARK: - CPU ↔ GPU Comparison
    // -------------------------------------------------------------------------
    
    private func compare(cpu: [CGPoint],
                         gpu: [CGPoint])
    -> (
        matches: [CGPoint],
        cpuOnly: [CGPoint],
        gpuOnly: [CGPoint],
        avgErr: CGFloat,
        maxErr: CGFloat,
        vectors: [(CGPoint, CGPoint)]
    )
    {
        var matches: [CGPoint] = []
        var cpuOnly: [CGPoint] = []
        var gpuRemain = gpu
        var vectors: [(CGPoint, CGPoint)] = []
        
        var sumErr: CGFloat = 0
        var maxErr: CGFloat = 0
        var count: CGFloat = 0
        
        for c in cpu {
            
            var bestD = CGFloat.greatestFiniteMagnitude
            var bestIdx: Int?
            var bestG: CGPoint?
            
            for (i, g) in gpuRemain.enumerated() {
                let dx = c.x - g.x
                let dy = c.y - g.y
                let d  = sqrt(dx*dx + dy*dy)
                
                if d < bestD {
                    bestD = d
                    bestIdx = i
                    bestG   = g
                }
            }
            
            if let idx = bestIdx, let g = bestG, bestD <= matchDist {
                matches.append(c)
                vectors.append((c, g))
                
                sumErr += bestD
                maxErr = max(maxErr, bestD)
                count += 1
                
                gpuRemain.remove(at: idx)
            }
            else {
                cpuOnly.append(c)
            }
        }
        
        return (
            matches,
            cpuOnly,
            gpuRemain,
            count > 0 ? (sumErr / count) : 0,
            maxErr,
            vectors
        )
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Heatmap
    // -------------------------------------------------------------------------
    
    private func makeHeatmapThrottled(cpu: [CGPoint],
                                      gpu: [CGPoint],
                                      roi: CGRect,
                                      fullSize: CGSize)
    -> MTLTexture?
    {
        guard fullSize.width > 32, fullSize.height > 32 else { return nil }
        guard roi.width > 8, roi.height > 8 else { return nil }
        
        heatmapCounter += 1
        if heatmapCounter % heatmapThrottle != 0 {
            return mode.mismatchHeatmapTexture
        }
        
        return makeHeatmap(cpu: cpu, gpu: gpu, roi: roi)
    }
    
    private func makeHeatmap(cpu: [CGPoint], gpu: [CGPoint], roi: CGRect)
    -> MTLTexture?
    {
        let w = Int(roi.width)
        let h = Int(roi.height)
        guard w > 0, h > 0 else { return nil }
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderWrite, .shaderRead]
        
        guard let tex = renderer.device.makeTexture(descriptor: desc) else { return nil }
        
        var grid = [UInt8](repeating: 0, count: w*h)
        var img  = [UInt8](repeating: 0, count: w*h*4)
        
        for p in cpu {
            let x = Int(p.x), y = Int(p.y)
            if x >= 0, x < w, y >= 0, y < h {
                grid[y*w + x] = 1
            }
        }
        
        for p in gpu {
            let x = Int(p.x), y = Int(p.y)
            if x >= 0, x < w, y >= 0, y < h {
                grid[y*w + x] = (grid[y*w + x] == 1 ? 3 : 2)
            }
        }
        
        for j in 0..<h {
            for i in 0..<w {
                let g = grid[j*w + i]
                let idx = (j*w + i) * 4
                
                switch g {
                case 3: img[idx] = 128; img[idx+1] = 128; img[idx+2] = 128; img[idx+3] = 180
                case 1: img[idx] =   0; img[idx+1] = 255; img[idx+2] =   0; img[idx+3] = 180
                case 2: img[idx] = 255; img[idx+1] =   0; img[idx+2] =   0; img[idx+3] = 180
                default: img[idx] = 0; img[idx+1] = 0; img[idx+2] = 0; img[idx+3] = 0
                }
            }
        }
        
        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: img,
            bytesPerRow: w * 4
        )
        
        return tex
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Public ROI Access
    // -------------------------------------------------------------------------
    
    func currentROI() -> CGRect  { lastROI }
    func currentFullSize() -> CGSize { lastFull }
    
    
    // -----------------------------------------------------------------------------
    // -----------------------------------------------------------------------------
    // MARK: - GPU Readback Detection (FAST9 texture path only)
    // -----------------------------------------------------------------------------
    
    private func detectGPU_Readback(
        pb: CVPixelBuffer,
        roi: CGRect,
        sr: Float,
        fullSize: CGSize
    ) {
        // ---------------------------------------------------------------------
        // 1. Configure detector thresholds
        // ---------------------------------------------------------------------
        detector.fast9ThresholdY = mode.fast9ThresholdY
        detector.fast9ScoreMinY  = mode.fast9ScoreMinY
        detector.nmsRadius       = mode.fast9NmsRadius
        
        // ---------------------------------------------------------------------
        // 2. Prepare frame (Y → edge)
        // ---------------------------------------------------------------------
        detector.prepareFrameY(
            pb,
            roi: roi,
            srScale: sr
        )
        
        // ---------------------------------------------------------------------
        // 3. FAST9 scored detection (GPU)
        // ---------------------------------------------------------------------
        let scoredPoints = detector.gpuFast9ScoredCornersY()
        
        // ---------------------------------------------------------------------
        // 3a. Relative score gating
        // ---------------------------------------------------------------------
        let sortedByScore = scoredPoints.sorted { $0.score > $1.score }
        
        let keepFraction: Float = 0.30
        let minKeep = 12
        let keepCount = max(
            Int(Float(sortedByScore.count) * keepFraction),
            minKeep
        )
        
        let scoreKept = Array(sortedByScore.prefix(keepCount))
        
        // ---------------------------------------------------------------------
        // 4. Hard volume cap
        // ---------------------------------------------------------------------
        let maxCorners = 800
        let capHit = scoreKept.count > maxCorners
        let capped = Array(scoreKept.prefix(maxCorners))
        
        let cappedPoints = capped.map { $0.point }
        
        // ---------------------------------------------------------------------
        // 5. Spatial NMS (cluster-thinning, not destructive)
        // ---------------------------------------------------------------------
        let nmsRadius = max(
            CGFloat(mode.fast9NmsRadius),
            min(roi.width, roi.height) * 0.08
        )
        
        let afterNMS: [CGPoint]
        
        if min(roi.width, roi.height) <= 120 {
            // Small ROI: skip NMS entirely
            afterNMS = cappedPoints
        } else {
            afterNMS = applyNMS(
                cappedPoints,
                radius: nmsRadius
            )
        }
        
        // ---------------------------------------------------------------------
        // 6. Density Gate
        // ---------------------------------------------------------------------
        let densityRadius = min(14, min(roi.width, roi.height) * 0.12)
        let densityMinNeighbors = 2
        
        let afterDensity = applyDensityGate(
            afterNMS,
            radius: densityRadius,
            minNeighbors: densityMinNeighbors
        )
        
        // ---------------------------------------------------------------------
        // 7. Density hysteresis (Coordinator-owned)
        // ---------------------------------------------------------------------
        // Density hysteresis: allow brief thinning
        let effectiveDensityCount = max(afterDensity.count, lastBallLockCount)
        
        // Treat weak-but-present as still valid
        let densityFloor = 8
        
        if effectiveDensityCount < densityFloor {
            ballLockMemory = nil
            lastBallLockCount = 0
            
            if DebugProbe.isEnabled(.capture) {
                print("[BALLLOCK] reset (density collapse)")
            }
            return
        }
        
        let maxDensityForBallLock = 150
        var finalBallLockPoints = Array(afterDensity.prefix(maxDensityForBallLock))
        
        // ---------------------------------------------------------------------
        // Density collapse handling with lock hysteresis
        // ---------------------------------------------------------------------

        if afterDensity.isEmpty {

            if ballLockMemory != nil && ballLockHoldFrames < maxHoldFrames {
                // Hold last lock through brief collapse
                ballLockHoldFrames += 1

                if DebugProbe.isEnabled(.capture) {
                    print("[BALLLOCK] holding lock through density drop age=\(ballLockHoldFrames)")
                }

                return
            } else {
                // True collapse
                ballLockHoldFrames = 0
                ballLockMemory = nil
                lastBallLockCount = 0

                if DebugProbe.isEnabled(.capture) {
                    print("[BALLLOCK] reset (density collapse)")
                }
            }
        }
        
        // ---------------------------------------------------------------------
        // 8. BallLock + temporal memory
        // ---------------------------------------------------------------------
        if let cluster = ballLock.findBallCluster(from: finalBallLockPoints) {

            ballLockHoldFrames = 0

            let alpha: Float = 0.3
            smoothedBallLockCount =
                alpha * Float(cluster.count) +
                (1 - alpha) * smoothedBallLockCount

            lastBallLockCount = Int(smoothedBallLockCount.rounded())

            ballLockMemory = BallLockMemory(
                lastCenter: cluster.center,
                lastRadius: cluster.radius,
                age: 0
            )

            if DebugProbe.isEnabled(.capture) {
                print("[BALLLOCK] lock maintained count=\(lastBallLockCount)")
            }

            // -----------------------------------------------------------------
            // MDG (Markerless Discrimination Gates) — PRE-POSE truth hardening
            // IMPORTANT:
            // - Do NOT modify BallLock state (memory/count/smoothing)
            // - Only gate "promotion to trusted evidence" downstream
            // -----------------------------------------------------------------
            let mdgDecision = mdg.evaluate(
                points: finalBallLockPoints,
                candidateCenter: cluster.center,
                candidateRadiusPx: cluster.radius,
                timestampSec: Double(frameIndex)
            )

            mdgBallLikeEvidence = mdgDecision.ballLikeEvidence
            mdgRejectReason = mdgDecision.reason

            // Example downstream gating (ONLY if you have a downstream consumer here):
            // if mdgBallLikeEvidence {
            //     // promote to RSWindow / pose-eligibility later
            // } else {
            //     // do NOT promote; refusal is correctness
            // }
        
        } else if var mem = ballLockMemory {
            
            // Density hysteresis: allow brief thinning
            let effectiveCount = max(finalBallLockPoints.count, lastBallLockCount)
            
            if effectiveCount < 8 {
                // True collapse
                ballLockMemory = nil
                lastBallLockCount = 0
                
                if DebugProbe.isEnabled(.capture) {
                    print("[BALLLOCK] reset (density collapse)")
                }
                
            } else if mem.age <= 3 {
                // Memory-assisted recovery
                let r = mem.lastRadius * 1.5
                let r2 = r * r
                
                let gated = finalBallLockPoints.filter {
                    let dx = $0.x - mem.lastCenter.x
                    let dy = $0.y - mem.lastCenter.y
                    return (dx * dx + dy * dy) <= r2
                }
                
                mem.age += 1
                ballLockMemory = mem
                finalBallLockPoints = gated
                
                if let cluster = ballLock.findBallCluster(from: finalBallLockPoints) {

                    let wasLocked = ballLockMemory != nil

                    lastBallLockCount = cluster.count

                    ballLockMemory = BallLockMemory(
                        lastCenter: cluster.center,
                        lastRadius: cluster.radius,
                        age: 0
                    )

                    if DebugProbe.isEnabled(.capture) {
                        if wasLocked {
                            print("[BALLLOCK] lock maintained count=\(cluster.count)")
                        } else {
                            print("[BALLLOCK] fresh lock count=\(cluster.count)")
                        }
                    }
                    
                } else if DebugProbe.isEnabled(.capture) {
                    print("[BALLLOCK] memory attempt failed age=\(mem.age)")
                }
                
            } else {
                // Memory expired
                ballLockMemory = nil
                lastBallLockCount = 0
                
                if DebugProbe.isEnabled(.capture) {
                    print("[BALLLOCK] reset (memory expired)")
                }
            }
            
            // ---------------------------------------------------------------------
            // 9. Log-first tuning
            // ---------------------------------------------------------------------
            if DebugProbe.isEnabled(.capture) {
                print("""
    [TUNING] frame=\(frameIndex)
    rawFAST9=\(scoredPoints.count)
    afterScore=\(scoreKept.count)
    capped=\(capped.count) capHit=\(capHit)
    afterNMS=\(afterNMS.count)
    afterDensity=\(afterDensity.count)
    ballLockIn=\(finalBallLockPoints.count)
    densityParams=(r:\(densityRadius), n:\(densityMinNeighbors))
    """)
            }
            
            // ---------------------------------------------------------------------
            // 10. Telemetry
            // ---------------------------------------------------------------------
            mode.updateTelemetry(
                cpu: [],
                gpu: finalBallLockPoints,
                matches: [],
                cpuOnly: [],
                gpuOnly: finalBallLockPoints,
                avgScore: 0,
                minScore: 0,
                maxScore: 0,
                clusterSize: finalBallLockPoints.count,
                avgErr: 0,
                maxErr: 0,
                vectors: []
            )
        }
    }
}
