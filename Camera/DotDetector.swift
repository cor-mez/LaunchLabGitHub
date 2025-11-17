//
//  DotDetector.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import simd

/// Stateless 2D dot detector
/// Produces VisionDot[] from the Y-plane of the camera buffer.
final class DotDetector {

    /// Main entry point
    func detectDots(
        yPtr: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        stride: Int,
        timestamp: Double
    ) -> [VisionDot] {

        var output: [VisionDot] = []
        output.reserveCapacity(32)

        // Simple fast threshold
        let threshold: UInt8 = 40

        var nextID = 0
        for y in 1..<(height-1) {
            let rowPtr = yPtr.advanced(by: y * stride)
            for x in 1..<(width-1) {

                let px = rowPtr[x]
                if px < threshold {
                    // simple centroid (no subpixel yet)
                    let pt = CGPoint(x: CGFloat(x), y: CGFloat(y))
                    let dot = VisionDot(
                        id: nextID,
                        position: pt,
                        predicted: nil,
                        confidence: 1.0,
                        fbError: 0.0
                    )
                    nextID += 1
                    output.append(dot)
                }
            }
        }

        return output
    }
}
