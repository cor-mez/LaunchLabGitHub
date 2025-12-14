// DotTestCoordinator.swift

import Foundation
import CoreVideo
import CoreGraphics
import Metal

@MainActor
final class DotTestCoordinator {

    static let shared = DotTestCoordinator()

    private let mode = DotTestMode.shared
    private let gpu = MetalDetector.shared
    private let renderer = MetalRenderer.shared

    private var lastROI: CGRect = .zero
    private var lastFullSize: CGSize = .zero

    private let matchDist: CGFloat = 2

    private var heatmapCounter = 0
    private let heatmapThrottle = 4       // generate heatmap every 4 frames (~60fps)

    private init() {}

    // MARK: - Public entrypoint
    func processFrame(_ pb: CVPixelBuffer) {

        // Prevent detection before the UI is ready
        guard mode.isArmedForDetection else { return }

        // Warmup: skip first N frames
        mode.warmupFrameCount += 1
        if mode.warmupFrameCount < mode.warmupFramesNeeded { return }

        // Ignore invalid / uninitialized buffers
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0 else { return }

        runDetection(on: pb)
    }

    // MARK: - Core Detection Dispatcher
    private func runDetection(on pb: CVPixelBuffer) {

        let fullW = CVPixelBufferGetWidth(pb)
        let fullH = CVPixelBufferGetHeight(pb)
        let fullSize = CGSize(width: fullW, height: fullH)

        // Abort if full frame dims are invalid
        guard fullW > 32, fullH > 32 else { return }
        lastFullSize = fullSize

        // Compute ROI safely
        let baseROI = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(fullW),
            height: CGFloat(fullH) * 0.5
        )

        let roi = mode.applyROI(to: baseROI, in: fullSize)
        guard roi.width >= 8, roi.height >= 8 else { return }
        lastROI = roi

        let sr = mode.srScale

        switch mode.backend {
        case .cpu:
            detectCPU(pb: pb, roi: roi, fullSize: fullSize)
        case .gpuY:
            detectGPU_Y(pb: pb, roi: roi, sr: sr, fullSize: fullSize)
        case .gpuCb:
            detectGPU_Cb(pb: pb, roi: roi, sr: sr, fullSize: fullSize)
        }
    }

    // MARK: - CPU FAST9 Path
    private func detectCPU(pb: CVPixelBuffer,
                           roi: CGRect,
                           fullSize: CGSize) {

        let cpuCorners = cpuDetect(pb: pb, roi: roi)

        mode.updateTelemetry(
            cpu: cpuCorners,
            gpu: [],
            matches: [],
            cpuOnly: cpuCorners,
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
                makeThrottledHeatmap(cpu: cpuCorners,
                                     gpu: [],
                                     roi: roi,
                                     fullSize: fullSize)
        }
    }

    // MARK: - GPU Y Path
    private func detectGPU_Y(pb: CVPixelBuffer,
                             roi: CGRect,
                             sr: Float,
                             fullSize: CGSize) {

        gpu.fast9ThresholdY = mode.fast9ThresholdY
        gpu.fast9ScoreMinY = mode.fast9ScoreMinY
        gpu.nmsRadius = mode.fast9NmsRadius

        gpu.prepareFrameY(pb, roi: roi, srScale: sr)

        let (gpuCorners, tele) = gpu.gpuFast9CornersYEnhanced()
        let cpuCorners = cpuDetect(pb: pb, roi: roi)

        let diff = compare(cpu: cpuCorners, gpu: gpuCorners)

        mode.updateTelemetry(
            cpu: cpuCorners,
            gpu: gpuCorners,
            matches: diff.matches,
            cpuOnly: diff.cpuOnly,
            gpuOnly: diff.gpuOnly,
            avgScore: tele.meanScore,
            minScore: tele.minValue,
            maxScore: tele.maxValue,
            clusterSize: diff.matches.count,
            avgErr: diff.avgErr,
            maxErr: diff.maxErr,
            vectors: diff.vectors
        )

        if mode.showHeatmap {
            mode.mismatchHeatmapTexture =
                makeThrottledHeatmap(cpu: cpuCorners,
                                     gpu: gpuCorners,
                                     roi: roi,
                                     fullSize: fullSize)
        }
    }

    // MARK: - GPU Cb Path
    private func detectGPU_Cb(pb: CVPixelBuffer,
                              roi: CGRect,
                              sr: Float,
                              fullSize: CGSize) {

        gpu.fast9ThresholdCb = mode.fast9ThresholdCb
        gpu.fast9ScoreMinCb = mode.fast9ScoreMinCb
        gpu.nmsRadius = mode.fast9NmsRadius

        gpu.prepareFrameCb(pb, roi: roi, srScale: sr)

        let (gpuCorners, tele) = gpu.gpuFast9CornersCbEnhanced()
        let cpuCorners = cpuDetect(pb: pb, roi: roi)

        let diff = compare(cpu: cpuCorners, gpu: gpuCorners)

        mode.updateTelemetry(
            cpu: cpuCorners,
            gpu: gpuCorners,
            matches: diff.matches,
            cpuOnly: diff.cpuOnly,
            gpuOnly: diff.gpuOnly,
            avgScore: tele.meanScore,
            minScore: tele.minValue,
            maxScore: tele.maxValue,
            clusterSize: diff.matches.count,
            avgErr: diff.avgErr,
            maxErr: diff.maxErr,
            vectors: diff.vectors
        )

        if mode.showHeatmap {
            mode.mismatchHeatmapTexture =
                makeThrottledHeatmap(cpu: cpuCorners,
                                     gpu: gpuCorners,
                                     roi: roi,
                                     fullSize: fullSize)
        }
    }

    // MARK: - CPU FAST9 Detector
    private func cpuDetect(pb: CVPixelBuffer, roi: CGRect) -> [CGPoint] {

        let r = roi.integral
        let w = Int(r.width)
        let h = Int(r.height)

        guard w > 8, h > 8 else { return [] }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return [] }

        let rb = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let src = yBase.assumingMemoryBound(to: UInt8.self)

        var buf = [UInt8](repeating: 0, count: w * h)
        let ox = Int(r.origin.x)
        let oy = Int(r.origin.y)

        for j in 0..<h {
            let srcRow = (oy + j) * rb
            let dst = j * w
            let rowPtr = src.advanced(by: srcRow + ox)
            for i in 0..<w {
                buf[dst + i] = rowPtr[i]
            }
        }

        let thr = mode.fast9ThresholdY

        let circle = [
            (0,-3),(1,-3),(2,-2),(3,-1),
            (3,0),(3,1),(2,2),(1,3),
            (0,3),(-1,3),(-2,2),(-3,1),
            (-3,0),(-3,-1),(-2,-2),(-1,-3)
        ]

        var out: [CGPoint] = []

        for y in 3..<(h-3) {
            let row = y * w
            for x in 3..<(w-3) {

                let center = Int(buf[row + x])
                var support = 0

                for (dx,dy) in circle {
                    let xx = x + dx
                    let yy = y + dy
                    let v = Int(buf[yy*w + xx])
                    if abs(v - center) > thr { support += 1 }
                }

                if support >= 9 {
                    out.append(CGPoint(x: x, y: y))
                }
            }
        }

        return out
    }

    // MARK: - CPU ↔ GPU Matching
    private func compare(cpu: [CGPoint],
                         gpu: [CGPoint]) -> (matches: [CGPoint],
                                             cpuOnly: [CGPoint],
                                             gpuOnly: [CGPoint],
                                             avgErr: CGFloat,
                                             maxErr: CGFloat,
                                             vectors: [(CGPoint, CGPoint)]) {

        var matches: [CGPoint] = []
        var cpuOnly: [CGPoint] = []
        var gpuRemaining = gpu
        var vectors: [(CGPoint, CGPoint)] = []

        var errSum: CGFloat = 0
        var errMax: CGFloat = 0
        var errCount: CGFloat = 0

        for c in cpu {

            var bestDist = CGFloat.greatestFiniteMagnitude
            var bestG: CGPoint?
            var bestIdx: Int?

            for (idx, g) in gpuRemaining.enumerated() {
                let dx = c.x - g.x
                let dy = c.y - g.y
                let d = sqrt(dx*dx + dy*dy)

                if d < bestDist {
                    bestDist = d
                    bestG = g
                    bestIdx = idx
                }
            }

            if let g = bestG,
               let idx = bestIdx,
               bestDist <= matchDist {

                matches.append(c)
                vectors.append((c, g))

                errSum += bestDist
                errMax = max(errMax, bestDist)
                errCount += 1

                gpuRemaining.remove(at: idx)
            }
            else {
                cpuOnly.append(c)
            }
        }

        let avgErr = errCount > 0 ? errSum / errCount : 0

        return (
            matches,
            cpuOnly,
            gpuRemaining,
            avgErr,
            errMax,
            vectors
        )
    }

    // MARK: - Heatmap Generator (Throttled)
    private func makeThrottledHeatmap(cpu: [CGPoint],
                                      gpu: [CGPoint],
                                      roi: CGRect,
                                      fullSize: CGSize) -> MTLTexture? {

        // Make sure dims are valid
        guard fullSize.width > 32, fullSize.height > 32 else { return nil }
        guard roi.width > 8, roi.height > 8 else { return nil }

        heatmapCounter += 1
        if heatmapCounter % heatmapThrottle != 0 {
            return mode.mismatchHeatmapTexture
        }

        return makeHeatmap(cpu: cpu,
                           gpu: gpu,
                           roi: roi,
                           fullSize: fullSize)
    }

    private func makeHeatmap(cpu: [CGPoint],
                             gpu: [CGPoint],
                             roi: CGRect,
                             fullSize: CGSize) -> MTLTexture? {

        let w = Int(roi.width)
        let h = Int(roi.height)
        guard w > 0, h > 0 else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false)

        desc.usage = [.shaderRead, .shaderWrite]

        guard let tex = renderer.device.makeTexture(descriptor: desc) else { return nil }

        var buf = [UInt8](repeating: 0, count: w*h*4)
        var grid = [UInt8](repeating: 0, count: w*h)

        for p in cpu {
            let x = Int(p.x)
            let y = Int(p.y)
            if x >= 0, x < w, y >= 0, y < h {
                grid[y*w + x] = 1
            }
        }

        for p in gpu {
            let x = Int(p.x)
            let y = Int(p.y)
            if x >= 0, x < w, y >= 0, y < h {
                grid[y*w + x] = (grid[y*w + x] == 1 ? 3 : 2)
            }
        }

        for j in 0..<h {
            for i in 0..<w {
                let idx = j*w + i
                let val = grid[idx]
                let bi = idx * 4

                switch val {
                case 3:
                    buf[bi] = 128; buf[bi+1] = 128; buf[bi+2] = 128; buf[bi+3] = 200
                case 1:
                    buf[bi] = 0; buf[bi+1] = 255; buf[bi+2] = 0; buf[bi+3] = 200
                case 2:
                    buf[bi] = 255; buf[bi+1] = 0; buf[bi+2] = 0; buf[bi+3] = 200
                default:
                    buf[bi] = 0; buf[bi+1] = 0; buf[bi+2] = 0; buf[bi+3] = 0
                }
            }
        }

        tex.replace(region: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0,
                    withBytes: buf,
                    bytesPerRow: w * 4)

        return tex
    }

    // MARK: - Public ROI/Size Accessors
    func currentROI() -> CGRect { lastROI }
    func currentFullSize() -> CGSize { lastFullSize }
}
