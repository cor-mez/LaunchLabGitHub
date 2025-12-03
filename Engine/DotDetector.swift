// File: Engine/DotDetector.swift
//
//  DotDetector.swift
//  LaunchLab
//
//  ORCHESTRATOR-ONLY MODULE
//  -------------------------
//  This file performs ZERO heavy image processing.
//  All real work is delegated to:
//    • DotDetector+ROI.swift
//    • DotDetector+Blue.swift
//    • DotDetector+Y.swift
//    • DotDetector+SR.swift
//    • DotDetector+FAST9.swift
//
//  Responsibilities:
//    1. Validate ROI
//    2. Lock/unlock pixel buffer
//    3. Crop Y + Cb ROI
//    4. Choose Blue / Y path
//    5. Preprocess via Blue or Y
//    6. Apply SR
//    7. Run FAST9
//    8. Map SR → full-frame
//    9. Build [CGPoint] + [VisionDot]
//   10. Free all buffers
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

public final class DotDetector {

    // MARK: - Stored properties (internal so extensions can access)
    internal let config: DotDetectorConfig
    let maxPoints: Int = 512

    // MARK: - Init
    public init(config: DotDetectorConfig = DotDetectorConfig()) {
        self.config = config
    }

    // MARK: - Unified Orchestrator Entry
    public func detectPoints(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect?
    ) -> ([CGPoint], [VisionDot]) {

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard frameWidth >= 16, frameHeight >= 16 else {
            return ([], [])
        }

        // STEP 0 — Lock pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // STEP 1 — Determine full-frame ROI
        let roiRect = validatedROI(
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            roiRaw: roi
        )
        if roiRect.isNull || roiRect.isEmpty {
            return ([], [])
        }

        // STEP 2 — Crop ROI (Y + optional Cb)
        let crop = cropROI(
            pixelBuffer: pixelBuffer,
            roiFullRect: roiRect
        )
        // crop.yROI, crop.cbROI, crop.roiRect

        // STEP 3 — Blue or Y path selection
        var preprocessedROI: vImage_Buffer = crop.yROI
        var usedBlue = false

        if config.useBlueChannel,
           var cbBuf = crop.cbROI,   // must be var for inout
           let normBlue = normalizeBlueROI(cbROI: &cbBuf,
                                           roiFullRect: crop.roiRect) {
            preprocessedROI = normBlue
            usedBlue = true
        }

        // If not blue, apply Y preprocessing
        if !usedBlue {
            preprocessedROI = preprocessYROI(
                preprocessedROI,
                gain: config.preFilterGain
            )
        }

        // STEP 4 — Apply SR
        let (srBuffer, scale) = applySR(
            roiBuffer: preprocessedROI,
            roiRect: crop.roiRect
        )

        // STEP 5 — FAST9 detection in SR space
        let rawCorners = fast9Detect(srBuffer)

        // STEP 6 — Map to full-frame coordinates
        var mapped: [CGPoint] = []
        mapped.reserveCapacity(rawCorners.count)

        let ox = crop.roiRect.origin.x
        let oy = crop.roiRect.origin.y
        let invScale = 1.0 / CGFloat(scale)

        for rc in rawCorners {
            let px = ox + CGFloat(rc.x) * invScale
            let py = oy + CGFloat(rc.y) * invScale
            mapped.append(CGPoint(x: px, y: py))
        }

        // STEP 7 — Build VisionDot array
        var vDots: [VisionDot] = []
        vDots.reserveCapacity(mapped.count)

        for (i, p) in mapped.enumerated() {
            let dot = VisionDot(
                id: i,
                position: p,
                score: rawCorners[i].score,
                predicted: nil,
                velocity: nil
            )
            vDots.append(dot)
        }

        // STEP 8 — Free all temporary buffers
        free(crop.yROI.data)
        if let cb = crop.cbROI {
            free(cb.data)
        }
        if scale > 1.0 {
            free(srBuffer.data)
        }
        // Free Blue preprocessed ROI if used
        if usedBlue,
           preprocessedROI.data != crop.yROI.data {
            free(preprocessedROI.data)
        }
        // Free Y preprocessed if different
        if !usedBlue,
           preprocessedROI.data != crop.yROI.data {
            free(preprocessedROI.data)
        }

        // STEP 9 — Return results
        return (mapped, vDots)
    }

    // MARK: - Convenience API (full-frame)
    public func detect(in pixelBuffer: CVPixelBuffer) -> [CGPoint] {
        let (pts, _) = detectPoints(pixelBuffer: pixelBuffer, roi: nil)
        return pts
    }

    // MARK: - Convenience API (ROI)
    public func detect(
        in pixelBuffer: CVPixelBuffer,
        roi: CGRect?
    ) -> [CGPoint] {
        let (pts, _) = detectPoints(pixelBuffer: pixelBuffer, roi: roi)
        return pts
    }

    // MARK: - ROI validation helper
    private func validatedROI(
        frameWidth: Int,
        frameHeight: Int,
        roiRaw: CGRect?
    ) -> CGRect {

        let full = CGRect(
            x: 0, y: 0,
            width: CGFloat(frameWidth),
            height: CGFloat(frameHeight)
        )

        var roi = roiRaw ?? full
        roi = roi.intersection(full)

        if roi.isNull || roi.isEmpty {
            return full
        }

        // Enforce minimum dimension 16×16
        let minSize: CGFloat = 16
        var x0 = Int(floor(roi.minX))
        var y0 = Int(floor(roi.minY))
        var x1 = Int(ceil(roi.maxX))
        var y1 = Int(ceil(roi.maxY))

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

        x0 = max(0, x0)
        y0 = max(0, y0)
        x1 = min(frameWidth, x1)
        y1 = min(frameHeight, y1)

        return CGRect(
            x: CGFloat(x0),
            y: CGFloat(y0),
            width: CGFloat(x1 - x0),
            height: CGFloat(y1 - y0)
        )
    }
}
