//
//  MarkerDetectorV1.swift
//  LaunchLab
//
//  MarkerDetector V1
//  Diamond marker detection via connected component + covariance geometry gate
//

import Foundation
import CoreVideo
import CoreGraphics
import Accelerate

final class MarkerDetectorV1 {

    // ---------------------------------------------------------------------
    // Tunables (LOCKED FOR V1)
    // ---------------------------------------------------------------------

    private let minAreaPx: Int = 80
    private let maxAreaPx: Int = 4000

    // Geometry gate
    private let minIsotropy: CGFloat = 0.55     // λ2 / λ1
    private let maxIsotropy: CGFloat = 1.80     // λ1 / λ2
    private let angleToleranceDeg: CGFloat = 20 // ± degrees around 45°

    // Black marker threshold (Y plane)
    private let blackThreshold: UInt8 = 90

    // ---------------------------------------------------------------------
    // Public API
    // ---------------------------------------------------------------------

    func detect(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> MarkerDetection? {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let roiX = Int(roi.origin.x)
        let roiY = Int(roi.origin.y)
        let roiW = Int(roi.width)
        let roiH = Int(roi.height)

        // -----------------------------------------------------------------
        // 1. Binary mask (black marker in Y plane)
        // -----------------------------------------------------------------

        var mask = [UInt8](repeating: 0, count: roiW * roiH)

        for y in 0..<roiH {
            let rowPtr = yBase
                .advanced(by: (roiY + y) * bytesPerRow + roiX)
                .assumingMemoryBound(to: UInt8.self)

            for x in 0..<roiW {
                mask[y * roiW + x] = rowPtr[x] < blackThreshold ? 255 : 0
            }
        }

        // -----------------------------------------------------------------
        // 2. Largest connected component
        // -----------------------------------------------------------------

        var visited = mask
        var best: [CGPoint] = []

        let neighbors = [(-1,0),(1,0),(0,-1),(0,1)]

        for y in 0..<roiH {
            for x in 0..<roiW {
                let idx = y * roiW + x
                if visited[idx] == 255 {

                    var stack = [(x, y)]
                    visited[idx] = 0
                    var pixels: [CGPoint] = []

                    while let (cx, cy) = stack.popLast() {
                        pixels.append(CGPoint(x: CGFloat(cx), y: CGFloat(cy)))

                        for (dx, dy) in neighbors {
                            let nx = cx + dx
                            let ny = cy + dy
                            if nx >= 0 && nx < roiW && ny >= 0 && ny < roiH {
                                let nidx = ny * roiW + nx
                                if visited[nidx] == 255 {
                                    visited[nidx] = 0
                                    stack.append((nx, ny))
                                }
                            }
                        }
                    }

                    if pixels.count >= minAreaPx && pixels.count <= maxAreaPx {
                        if pixels.count > best.count {
                            best = pixels
                        }
                    }
                }
            }
        }

        guard !best.isEmpty else { return nil }

        // -----------------------------------------------------------------
        // 3. Covariance geometry gate (diamond test)
        // -----------------------------------------------------------------

        let n = CGFloat(best.count)

        var meanX: CGFloat = 0
        var meanY: CGFloat = 0
        for p in best {
            meanX += p.x
            meanY += p.y
        }
        meanX /= n
        meanY /= n

        var cxx: CGFloat = 0
        var cyy: CGFloat = 0
        var cxy: CGFloat = 0

        for p in best {
            let dx = p.x - meanX
            let dy = p.y - meanY
            cxx += dx * dx
            cyy += dy * dy
            cxy += dx * dy
        }

        cxx /= n
        cyy /= n
        cxy /= n

        let trace = cxx + cyy
        let det = cxx * cyy - cxy * cxy
        let disc = max(trace * trace / 4 - det, 0)

        let lambda1 = trace / 2 + sqrt(disc)
        let lambda2 = trace / 2 - sqrt(disc)

        guard lambda1 > 0, lambda2 > 0 else { return nil }

        let isotropy = lambda2 / lambda1
        guard isotropy >= minIsotropy && (1 / isotropy) <= maxIsotropy else {
            return nil
        }

        let angleRad = 0.5 * atan2(2 * cxy, cxx - cyy)
        let angleDeg = abs(angleRad * 180 / .pi)

        let isDiamond =
            abs(angleDeg - 45) <= angleToleranceDeg ||
            abs(angleDeg - 135) <= angleToleranceDeg

        guard isDiamond else { return nil }

        // -----------------------------------------------------------------
        // 4. Output
        // -----------------------------------------------------------------

        let center = CGPoint(
            x: roi.origin.x + meanX,
            y: roi.origin.y + meanY
        )

        let sizePx: CGFloat = (lambda1 + lambda2).squareRoot()

        let confidence: CGFloat = min(1.0, CGFloat(best.count) / 300.0)

        return MarkerDetection(
            center: center,
            sizePx: sizePx,
            confidence: confidence
        )
    }
}
