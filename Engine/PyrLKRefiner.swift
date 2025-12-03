//
//  PyrLKRefiner.swift
//  LaunchLab
//
//  Stateless CPU-based Lucas–Kanade refinement.
//

import Foundation
import CoreVideo
import CoreGraphics
import simd

public final class PyrLKRefiner {

    private let windowRadius: Int = 4
    private let maxIterations: Int = 8
    private let epsilon: Float = 0.01

    public init() {}

    public func refine(
        dots: [VisionDot],
        prevBuffer: CVPixelBuffer,
        currBuffer: CVPixelBuffer
    ) -> ([VisionDot], [SIMD2<Float>]) {

        guard !dots.isEmpty else { return (dots, []) }

        CVPixelBufferLockBaseAddress(prevBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(currBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(prevBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(currBuffer, .readOnly)
        }

        guard
            let prevBase = CVPixelBufferGetBaseAddressOfPlane(prevBuffer, 0),
            let currBase = CVPixelBufferGetBaseAddressOfPlane(currBuffer, 0)
        else {
            return (dots, Array(repeating: SIMD2<Float>.zero, count: dots.count))
        }

        let width  = CVPixelBufferGetWidth(prevBuffer)
        let height = CVPixelBufferGetHeight(prevBuffer)

        let prevStride = CVPixelBufferGetBytesPerRowOfPlane(prevBuffer, 0)
        let currStride = CVPixelBufferGetBytesPerRowOfPlane(currBuffer, 0)

        let prevLuma = prevBase.bindMemory(to: UInt8.self, capacity: height * prevStride)
        let currLuma = currBase.bindMemory(to: UInt8.self, capacity: height * currStride)

        var refinedDots: [VisionDot] = []
        refinedDots.reserveCapacity(dots.count)

        var flows: [SIMD2<Float>] = []
        flows.reserveCapacity(dots.count)

        for dot in dots {
            let (refined, flow) = refineOne(
                dot: dot,
                prevLuma: prevLuma,
                currLuma: currLuma,
                width: width,
                height: height,
                prevStride: prevStride,
                currStride: currStride
            )
            refinedDots.append(refined)
            flows.append(flow)
        }

        return (refinedDots, flows)
    }

    // MARK: - Per-Dot refinement
    private func refineOne(
        dot: VisionDot,
        prevLuma: UnsafePointer<UInt8>,
        currLuma: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        prevStride: Int,
        currStride: Int
    ) -> (VisionDot, SIMD2<Float>) {

        var x = Float(dot.position.x)
        var y = Float(dot.position.y)

        let originalX = x
        let originalY = y

        let r = windowRadius

        for _ in 0..<maxIterations {

            if Int(x) - r < 1 || Int(x) + r >= width - 1 ||
               Int(y) - r < 1 || Int(y) + r >= height - 1 {
                break
            }

            var G = simd_float2x2(0)
            var b = SIMD2<Float>(0, 0)

            for wy in -r...r {
                for wx in -r...r {
                    let px = Int(x) + wx
                    let py = Int(y) + wy

                    let I1 = Float(prevLuma[py * prevStride + px])

                    let Ix = 0.5 * (
                        Float(prevLuma[py * prevStride + (px + 1)]) -
                        Float(prevLuma[py * prevStride + (px - 1)])
                    )
                    let Iy = 0.5 * (
                        Float(prevLuma[(py + 1) * prevStride + px]) -
                        Float(prevLuma[(py - 1) * prevStride + px])
                    )

                    let I2 = Float(currLuma[py * currStride + px])
                    let It = I2 - I1

                    let g = SIMD2<Float>(Ix, Iy)

                    G += simd_float2x2(
                        SIMD2<Float>(g.x * g.x, g.x * g.y),
                        SIMD2<Float>(g.y * g.x, g.y * g.y)
                    )

                    b += g * It
                }
            }

            let det = G[0,0] * G[1,1] - G[0,1] * G[1,0]
            if abs(det) < 1e-6 { break }

            let inv = simd_float2x2(
                SIMD2<Float>( G[1,1], -G[0,1]),
                SIMD2<Float>(-G[1,0],  G[0,0])
            ) * (1.0 / det)

            let d = -(inv * b)

            x += d.x
            y += d.y

            if simd_length(d) < epsilon { break }
        }

        let refinedPos = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let flow = SIMD2<Float>(x - originalX, y - originalY)

        let refinedDot = VisionDot(
            id: dot.id,
            position: refinedPos,
            score: dot.score,      // ← KEEP SCORE
            predicted: dot.predicted,
            velocity: dot.velocity
        )

        return (refinedDot, flow)
    }
}
