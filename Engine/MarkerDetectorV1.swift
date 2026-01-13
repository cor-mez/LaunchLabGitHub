//
//  MarkerDetectorV0.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import CoreGraphics
import Accelerate

final class MarkerDetectorV0 {

    // ---------------------------------------------------------------------
    // Tunable parameters (V0 locked)
    // ---------------------------------------------------------------------

    private let minAreaPx: CGFloat = 80        // reject speckle
    private let maxAreaPx: CGFloat = 4000      // reject turf blobs
    private let minAspectRatio: CGFloat = 0.7 // diamond tolerance
    private let maxAspectRatio: CGFloat = 1.3
    private let minEdgeEnergy: Float = 12.0

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

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let roiX = Int(roi.origin.x)
        let roiY = Int(roi.origin.y)
        let roiW = Int(roi.width)
        let roiH = Int(roi.height)

        var mask = [UInt8](repeating: 0, count: roiW * roiH)

        // -----------------------------------------------------------------
        // 1. Simple luminance threshold (black marker)
        // -----------------------------------------------------------------

        let threshold: UInt8 = 90

        for y in 0..<roiH {
            let rowPtr = yBase.advanced(by: (roiY + y) * bytesPerRow + roiX)
                .assumingMemoryBound(to: UInt8.self)

            for x in 0..<roiW {
                let v = rowPtr[x]
                mask[y * roiW + x] = v < threshold ? 255 : 0
            }
        }

        // -----------------------------------------------------------------
        // 2. Connected component (single-pass flood)
        // -----------------------------------------------------------------

        var visited = mask
        var bestBlob: (area: Int, minX: Int, maxX: Int, minY: Int, maxY: Int)?
        let directions = [(-1,0),(1,0),(0,-1),(0,1)]

        for y in 0..<roiH {
            for x in 0..<roiW {
                let idx = y * roiW + x
                if visited[idx] == 255 {

                    var stack = [(x,y)]
                    visited[idx] = 0

                    var area = 0
                    var minX = x, maxX = x
                    var minY = y, maxY = y

                    while let (cx,cy) = stack.popLast() {
                        area += 1
                        minX = min(minX, cx)
                        maxX = max(maxX, cx)
                        minY = min(minY, cy)
                        maxY = max(maxY, cy)

                        for (dx,dy) in directions {
                            let nx = cx + dx
                            let ny = cy + dy
                            if nx >= 0 && nx < roiW && ny >= 0 && ny < roiH {
                                let nidx = ny * roiW + nx
                                if visited[nidx] == 255 {
                                    visited[nidx] = 0
                                    stack.append((nx,ny))
                                }
                            }
                        }
                    }

                    if area > Int(minAreaPx) && area < Int(maxAreaPx) {
                        if bestBlob == nil || area > bestBlob!.area {
                            bestBlob = (area, minX, maxX, minY, maxY)
                        }
                    }
                }
            }
        }

        guard let blob = bestBlob else {
            return nil
        }

        // -----------------------------------------------------------------
        // 3. Geometry sanity checks (diamond-ish)
        // -----------------------------------------------------------------

        let w = CGFloat(blob.maxX - blob.minX + 1)
        let h = CGFloat(blob.maxY - blob.minY + 1)
        let aspect = w / h

        guard aspect > minAspectRatio && aspect < maxAspectRatio else {
            return nil
        }

        // -----------------------------------------------------------------
        // 4. Output
        // -----------------------------------------------------------------

        let center = CGPoint(
            x: roi.origin.x + CGFloat(blob.minX) + w * 0.5,
            y: roi.origin.y + CGFloat(blob.minY) + h * 0.5
        )

        let confidence = min(CGFloat(1.0), CGFloat(blob.area) / 400.0)
        return MarkerDetection(
            center: center,
            sizePx: max(w,h),
            confidence: confidence
        )
    }
}
