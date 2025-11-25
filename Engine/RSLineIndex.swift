//
//  RSLineIndex.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

public enum RSLineIndex {

    /// Compute the RS row index for each VisionDot.
    /// row = floor(y) clamped to image height bounds.
    public static func indexForDots(
        _ dots: [VisionDot],
        height: Int
    ) -> [Int] {

        guard height > 0 else {
            return Array(repeating: 0, count: dots.count)
        }

        let maxRow = height - 1

        return dots.map { dot in
            let y = Int(floor(dot.position.y))
            if y < 0 { return 0 }
            if y > maxRow { return maxRow }
            return y
        }
    }
}
