//
//  BlobSeedDetector.swift
//  LaunchLab
//
//  Blob-first luminance detector for golf balls.
//  OBSERVATIONAL ONLY — no authority.
//  CPU-based by design for determinism.
//

import CoreGraphics
import CoreVideo

struct BlobSeed {
    let center: CGPoint
    let area: Int
    let circularity: Double
}

final class BlobSeedDetector {

    // MARK: - Tunables (conservative, screen-tested)

    private let minArea: Int = 250
    private let maxArea: Int = 5000

    private let minCircularity: Double = 0.55

    // Adaptive thresholding
    private let thresholdBias: Int = 18

    // MARK: - Public API

    func detectBlob(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> BlobSeed? {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard
            let rawBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else {
            return nil
        }

        // 🔒 Bind raw pointer to UInt8 luminance
        let base = rawBase.bindMemory(
            to: UInt8.self,
            capacity: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        )

        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let roiX = max(0, Int(roi.origin.x))
        let roiY = max(0, Int(roi.origin.y))
        let roiW = min(Int(roi.width), width - roiX)
        let roiH = min(Int(roi.height), height - roiY)

        // --------------------------------------------------
        // 1. Compute local mean luminance
        // --------------------------------------------------

        var sum = 0
        var count = 0

        for y in roiY..<(roiY + roiH) {
            let row = base.advanced(by: y * stride)
            for x in roiX..<(roiX + roiW) {
                sum += Int(row[x])
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let mean = sum / count
        let threshold = max(0, mean - thresholdBias)

        // --------------------------------------------------
        // 2. Flood-fill connected bright regions
        // --------------------------------------------------

        var visited = Set<Int>()
        var bestBlob: [CGPoint] = []

        @inline(__always)
        func index(_ x: Int, _ y: Int) -> Int {
            y * width + x
        }

        for y in roiY..<(roiY + roiH) {
            for x in roiX..<(roiX + roiW) {

                let idx = index(x, y)
                if visited.contains(idx) { continue }

                let px = base[y * stride + x]
                if Int(px) < threshold { continue }

                // BFS flood fill
                var stack = [(x, y)]
                var blob: [CGPoint] = []

                while let (cx, cy) = stack.popLast() {
                    let i = index(cx, cy)
                    if visited.contains(i) { continue }
                    visited.insert(i)

                    let val = base[cy * stride + cx]
                    if Int(val) < threshold { continue }

                    blob.append(CGPoint(x: cx, y: cy))

                    if cx > roiX { stack.append((cx - 1, cy)) }
                    if cx < roiX + roiW - 1 { stack.append((cx + 1, cy)) }
                    if cy > roiY { stack.append((cx, cy - 1)) }
                    if cy < roiY + roiH - 1 { stack.append((cx, cy + 1)) }
                }

                if blob.count > bestBlob.count {
                    bestBlob = blob
                }
            }
        }

        // --------------------------------------------------
        // 3. Area gate
        // --------------------------------------------------

        guard bestBlob.count >= minArea,
              bestBlob.count <= maxArea
        else { return nil }

        // --------------------------------------------------
        // 4. Geometry (centroid + circularity)
        // --------------------------------------------------

        let sumPt = bestBlob.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }

        let center = CGPoint(
            x: sumPt.x / CGFloat(bestBlob.count),
            y: sumPt.y / CGFloat(bestBlob.count)
        )

        var maxR: Double = 0
        var minR: Double = Double.greatestFiniteMagnitude

        for p in bestBlob {
            let d = hypot(
                Double(p.x - center.x),
                Double(p.y - center.y)
            )
            maxR = max(maxR, d)
            minR = min(minR, d)
        }

        guard minR > 1 else { return nil }

        let circularity = minR / maxR
        guard circularity >= minCircularity else { return nil }

        // --------------------------------------------------
        // 5. Accept
        // --------------------------------------------------

        return BlobSeed(
            center: center,
            area: bestBlob.count,
            circularity: circularity
        )
    }
}
