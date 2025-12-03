// File: Engine/DotDetector+FAST9.swift
//
//  FAST9 corner detector module for DotDetector.
//

import Foundation
import Accelerate

extension DotDetector {

    public struct RawCorner {
        public let x: Int
        public let y: Int
        public let score: Float
    }

    func fast9Detect(_ srBuffer: vImage_Buffer) -> [RawCorner] {

        let width = Int(srBuffer.width)
        let height = Int(srBuffer.height)
        let rowBytes = srBuffer.rowBytes

        guard width >= 7, height >= 7 else { return [] }

        let ptr = srBuffer.data.assumingMemoryBound(to: UInt8.self)

        let thrFast: Int = max(1, config.fast9Threshold)
        let thrLocal: Int = max(1, Int(config.vImageThreshold))
        let cornerScoreMin: Float = Float(thrFast) * 0.8

        let circleOffsets: [(dx: Int, dy: Int)] = [
            ( 0, -3), ( 1, -3), ( 2, -2), ( 3, -1),
            ( 3,  0), ( 3,  1), ( 2,  2), ( 1,  3),
            ( 0,  3), (-1,  3), (-2,  2), (-3,  1),
            (-3,  0), (-3, -1), (-2, -2), (-1, -3)
        ]

        var results: [RawCorner] = []
        results.reserveCapacity(256)

        let margin = 3

        for y in margin ..< (height - margin) {
            let rowOffset = y * rowBytes

            for x in margin ..< (width - margin) {

                let idx = rowOffset + x
                let centerVal = Int(ptr[idx])

                // Quick 4-neighbor reject
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

                let score = Float(minDiffOnArc)
                if score < cornerScoreMin { continue }

                results.append(RawCorner(x: x, y: y, score: score))

                if results.count >= maxPoints {
                    return results
                }
            }
        }

        return results
    }
}