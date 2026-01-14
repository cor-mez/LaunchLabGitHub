//
//  MarkerDetector+Black.swift
//  LaunchLab
//
//  CPU-only black diamond detector
//

import Foundation
import CoreGraphics
import CoreVideo

extension MarkerDetectorV1{

    // ---------------------------------------------------------------------
    // MARK: - Black Marker Detection (Y Plane)
    // ---------------------------------------------------------------------

    func detectBlackDiamond(
        yPlane: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        roi: CGRect
    ) -> MarkerDetection? {

        let minX = max(Int(roi.minX), 0)
        let maxX = min(Int(roi.maxX), width - 1)
        let minY = max(Int(roi.minY), 0)
        let maxY = min(Int(roi.maxY), height - 1)

        // -----------------------------------------------------------------
        // Compute local mean luminance inside ROI
        // -----------------------------------------------------------------

        var sum: Int = 0
        var count: Int = 0

        for y in minY..<maxY {
            let row = yPlane.advanced(by: y * bytesPerRow)
            for x in minX..<maxX {
                sum += Int(row[x])
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let meanLuma: Int = sum / count
        let darkThreshold: Int = meanLuma - 25   // tunable

        // -----------------------------------------------------------------
        // Accumulate dark pixels
        // -----------------------------------------------------------------

        var accumX: Int = 0
        var accumY: Int = 0
        var darkCount: Int = 0

        for y in minY..<maxY {
            let row = yPlane.advanced(by: y * bytesPerRow)
            for x in minX..<maxX {
                if Int(row[x]) < darkThreshold {
                    accumX += x
                    accumY += y
                    darkCount += 1
                }
            }
        }

        // Minimum area gate (~10 mm marker heuristic)
        if darkCount < 60 {
            return nil
        }

        // -----------------------------------------------------------------
        // Compute centroid
        // -----------------------------------------------------------------

        let cx = CGFloat(accumX) / CGFloat(darkCount)
        let cy = CGFloat(accumY) / CGFloat(darkCount)

        // -----------------------------------------------------------------
        // Estimate size (sqrt of area)
        // -----------------------------------------------------------------

        let sizePx = CGFloat(sqrt(Double(darkCount)))

        // -----------------------------------------------------------------
        // Confidence heuristic
        // -----------------------------------------------------------------

        let confidence = min(1.0, CGFloat(darkCount) / 400.0)

        return MarkerDetection(
            center: CGPoint(x: cx, y: cy),
            sizePx: sizePx,
            confidence: confidence
        )
    }
}
