//
//  RSLineIndex.swift
//  LaunchLab
//

import Foundation
import simd

/// Computes which sensor row each dot lies on.
/// This is a simple linear mapping used for RS timestamp estimation.
final class RSLineIndex {

    /// Returns an array of line indices, one per dot.
    /// Assumes the imagePoints are in pixel coordinates.
    public func compute(
        frame: VisionFrameData,
        imagePoints: [SIMD2<Float>]
    ) -> [Int] {

        let h = Float(frame.height)
        var out = [Int]()
        out.reserveCapacity(imagePoints.count)

        for p in imagePoints {
            let y = max(0, min(h - 1, p.y))
            out.append(Int(y))
        }

        return out
    }
}