//  RSGeometricCorrector.swift
//  LaunchLab
//

import Foundation
import CoreGraphics

public enum RSGeometricCorrector {

    public static func correct(
        dots: [VisionDot],
        bearings: [RSBearing],
        timing: RSTimingModel
    ) -> [RSCorrectedPoint] {

        let count = min(dots.count, bearings.count)
        guard count > 0 else { return [] }

        var out: [RSCorrectedPoint] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let d = dots[i]
            let b = bearings[i]
            let ts = timing.timestampForRow(b.rowIndex)

            // Placeholder: unwarp = original
            out.append(
                RSCorrectedPoint(
                    original: d.position,
                    corrected: d.position,
                    timestamp: ts
                )
            )
        }

        return out
    }
}
