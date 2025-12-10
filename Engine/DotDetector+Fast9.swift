//
//  DotDetector+FAST9.swift
//  LaunchLab
//
//  Restored FAST9 implementation — REQUIRED by DebugFAST9 wrapper.
//  DO NOT MODIFY. This is the core corner detector.
//

import Foundation
import Accelerate

extension DotDetector {

    /// Raw FAST9 corner output (SR-space coordinates).
    public struct RawCorner {
        public let x: Int
        public let y: Int
        public let score: Float
    }

    /// FAST9 corner detection on Planar8 vImage buffer.
    internal func fast9Detect(_ srBuffer: vImage_Buffer) -> [RawCorner] {

        let width  = Int(srBuffer.width)
        let height = Int(srBuffer.height)
        let stride = srBuffer.rowBytes

        guard width > 6, height > 6 else { return [] }

        let ptr = srBuffer.data.assumingMemoryBound(to: UInt8.self)

        // Thresholds
        let thrFast  = max(1, config.fast9Threshold)
        let thrLocal = max(1, Int(config.vImageThreshold))
        let scoreMin = Float(thrFast) * 0.8

        // FAST9 circle offsets
        let circle: [(dx: Int, dy: Int)] = [
            ( 0,-3), ( 1,-3), ( 2,-2), ( 3,-1),
            ( 3, 0), ( 3, 1), ( 2, 2), ( 1, 3),
            ( 0, 3), (-1, 3), (-2, 2), (-3, 1),
            (-3, 0), (-3,-1), (-2,-2), (-1,-3)
        ]

        var out: [RawCorner] = []
        out.reserveCapacity(256)

        let margin = 3

        for y in margin ..< (height - margin) {

            let row = y * stride

            for x in margin ..< (width - margin) {

                let idx = row + x
                let center = Int(ptr[idx])

                // Quick reject (local contrast)
                let up    = Int(ptr[idx - stride])
                let down  = Int(ptr[idx + stride])
                let left  = Int(ptr[idx - 1])
                let right = Int(ptr[idx + 1])

                let maxDiff = max(
                    abs(up - center),
                    abs(down - center),
                    abs(left - center),
                    abs(right - center)
                )

                if maxDiff < thrLocal { continue }

                // Full 16-point FAST9 test
                var brighter = 0
                var darker   = 0
                var minOnArc = Int.max

                for o in circle {
                    let nIdx = (y + o.dy) * stride + (x + o.dx)
                    let v = Int(ptr[nIdx])
                    let d = v - center

                    if d >= thrFast {
                        brighter += 1
                        minOnArc = min(minOnArc, d)
                    } else if d <= -thrFast {
                        darker += 1
                        minOnArc = min(minOnArc, -d)
                    }
                }

                let support = max(brighter, darker)
                if support < 9 { continue }

                let score = Float(minOnArc)
                if score < scoreMin { continue }

                out.append(.init(x: x, y: y, score: score))
                if out.count >= maxPoints { return out }
            }
        }

        return out
    }
}
