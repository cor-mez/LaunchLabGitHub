//
//  DotDetector.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

public final class DotDetector {

    internal let config: DotDetectorConfig
    internal let maxPoints: Int = 512

    public init(config: DotDetectorConfig = DotDetectorConfig()) {
        self.config = config
    }
    
    // MARK: - Public API (NORMAL DETECTION)

    public func detectPoints(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect?
    ) -> ([CGPoint], [VisionDot]) {

        let (pts, dots, pre, sr) = detectWithFAST9Buffers(
            pixelBuffer: pixelBuffer,
            roi: roi
        )

        if var p = pre {
            p.freeSelf()
        }
        if var s = sr {
            s.freeSelf()
        }

        return (pts, dots)
    }

    /// Convenience — full‐frame detection of CGPoint list
    public func detect(in pixelBuffer: CVPixelBuffer) -> [CGPoint] {
        let (pts, _) = detectPoints(pixelBuffer: pixelBuffer, roi: nil)
        return pts
    }

    /// Convenience — ROI detection of CGPoint list
    public func detect(in pixelBuffer: CVPixelBuffer, roi: CGRect?) -> [CGPoint] {
        let (pts, _) = detectPoints(pixelBuffer: pixelBuffer, roi: roi)
        return pts
    }
}


// ---------------------------------------------------------
// MARK: - ROI Validation Helper
// ---------------------------------------------------------

extension DotDetector {

    internal func validatedROI(
        frameWidth: Int,
        frameHeight: Int,
        roiRaw: CGRect?
    ) -> CGRect {

        let full = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(frameWidth),
            height: CGFloat(frameHeight)
        )

        guard var roi = roiRaw else { return full }
        roi = roi.intersection(full)

        if roi.isNull || roi.isEmpty {
            return full
        }

        // Ensure minimum size = 16×16
        let minSize: CGFloat = 16

        var x0 = Int(floor(roi.minX))
        var y0 = Int(floor(roi.minY))
        var x1 = Int(ceil(roi.maxX))
        var y1 = Int(ceil(roi.maxY))

        // Expand ROI if too small
        if x1 - x0 < Int(minSize) {
            let mid = (x0 + x1) / 2
            x0 = mid - Int(minSize / 2)
            x1 = mid + Int(minSize / 2)
        }
        if y1 - y0 < Int(minSize) {
            let mid = (y0 + y1) / 2
            y0 = mid - Int(minSize / 2)
            y1 = mid + Int(minSize / 2)
        }

        // Clamp to full frame
        x0 = max(0, x0)
        y0 = max(0, y0)
        x1 = min(frameWidth,  x1)
        y1 = min(frameHeight, y1)

        return CGRect(
            x: CGFloat(x0),
            y: CGFloat(y0),
            width: CGFloat(x1 - x0),
            height: CGFloat(y1 - y0)
        )
    }
}
