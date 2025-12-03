//
//  DotDetector+FAST9.swift
//  LaunchLab
//
//  FAST9 corner detector module for DotDetector.
//  Operates ONLY on the SR-scaled Planar8 ROI buffer.
//
//  Inputs:
//    – srBuffer: vImage_Buffer (Planar8), already SR-scaled,
//                already normalized (if Blue mode),
//                already gain-adjusted.
//
//  Outputs:
//    – [RawCorner]: raw integer corner coordinates in SR space,
//                   NOT mapped to full-frame.
//

import Foundation
import Accelerate

extension DotDetector {

    // Raw FAST9 corner output (SR-space coordinates).
    public struct RawCorner {
        public let x: Int
        public let y: Int
        public let score: Float
    }

    /// FAST9 corner detection in SR space.
    ///
    /// - Parameter srBuffer: Planar8 vImage_Buffer (scaled ROI)
    /// - Returns: [RawCorner] up to maxPoints
    ///
    func fast9Detect(_ srBuffer: vImage_Buffer) -> [RawCorner] {

        let width = Int(srBuffer.width)
        let height = Int(srBuffer.height)
        let rowBytes = srBuffer.rowBytes

        guard width >= 7, height >= 7 else { return [] }

        let ptr = srBuffer.data.assumingMemoryBound(to: UInt8.self)

        // FAST9 thresholds (explicit Ints/Floats – NO Float16)
        let thrFast: Int = max(1, config.fast9Threshold)
        let thrLocal: Int = max(1, Int(config.vImageThreshold))
        let cornerScoreMin: Float = Float(thrFast) * 0.8

        // Strict FAST9 circle offsets
        let circleOffsets: [(dx: Int, dy: Int)] = [
            ( 0, -3), ( 1, -3), ( 2, -2), ( 3, -1),
            ( 3,  0), ( 3,  1), ( 2,  2), ( 1,  3),
            ( 0,  3), (-1,  3), (-2,  2), (-3,  1),
            (-3,  0), (-3, -1), (-2, -2), (-1, -3)
        ]

        var results: [RawCorner] = []
        results.reserveCapacity(256)

        let margin = 3

        // LOOP
        for y in margin ..< (height - margin) {

            let rowOffset = y * rowBytes

            for x in margin ..< (width - margin) {

                let idx = rowOffset + x
                let centerVal = Int(ptr[idx])

                // -------------------------------------------------
                // STEP 1: Quick reject using 4-neighborhood
                // -------------------------------------------------
                let rightVal = Int(ptr[idx + 1])
                let leftVal  = Int(ptr[idx - 1])
                let upVal    = Int(ptr[idx - rowBytes])
                let downVal  = Int(ptr[idx + rowBytes])

                var maxDiff = 0
                maxDiff = max(maxDiff, abs(rightVal - centerVal))
                maxDiff = max(maxDiff, abs(leftVal  - centerVal))
                maxDiff = max(maxDiff, abs(upVal    - centerVal))
                maxDiff = max(maxDiff, abs(downVal  - centerVal))

                if maxDiff < thrLocal {
                    continue
                }

                // -------------------------------------------------
                // STEP 2: 16-point FAST9 arc
                // -------------------------------------------------
                var brighter = 0
                var darker   = 0
                var minDiffOnArc = Int.max

                for o in circleOffsets {
                    let nIdx = (y + o.dy) * rowBytes + (x + o.dx)
                    let nVal = Int(ptr[nIdx])
                    let diff = nVal - centerVal

                    if diff >= thrFast {
                        brighter += 1
                        let ad = diff
                        if ad < minDiffOnArc { minDiffOnArc = ad }
                    } else if diff <= -thrFast {
                        darker += 1
                        let ad = -diff
                        if ad < minDiffOnArc { minDiffOnArc = ad }
                    }
                }

                let support = max(brighter, darker)
                if support < 9 { continue }

                // -------------------------------------------------
                // STEP 3: score check
                // -------------------------------------------------
                let score = Float(minDiffOnArc)
                if score < cornerScoreMin { continue }

                // -------------------------------------------------
                // STEP 4: record corner
                // -------------------------------------------------
                results.append(RawCorner(x: x, y: y, score: score))

                if results.count >= maxPoints {
                    return results
                }
            }
        }

        return results
    }
}
