//
//  DotDetector+DebugFast9.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

extension DotDetector {
    
    public func detectWithFAST9Buffers(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect?
    ) -> (
        points: [CGPoint],
        visionDots: [VisionDot],
        preFast9: vImage_Buffer?,
        srFast9: vImage_Buffer?
    ) {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        
        let roiRect = validatedROI(
            frameWidth: w,
            frameHeight: h,
            roiRaw: roi
        )
        
        // ---------------------------
        // ROI crop (Y + Cb)
        // ---------------------------
        let crop = cropROI(pixelBuffer: pixelBuffer, roiFullRect: roiRect)
        var yBuf  = crop.yROI
        var cbBuf = crop.cbROI
        
        var preFast9: vImage_Buffer? = nil
        
        if config.useBlueChannel, var cb = cbBuf {
            preFast9 = buildBlueEnhancedROI(cbROI: &cb)
        }
        
        // fallback → Y
        if preFast9 == nil {
            preFast9 = preprocessYROI(yBuf, gain: config.preFilterGain)
        }
        
        guard var pre = preFast9 else {
            yBuf.freeSelf()
            if var cb = cbBuf {
                cb.freeSelf()
            }
            return ([], [], nil, nil)
        }
        
        // super-resolution
        let (srBuf, srScale) = applySR(
            roiBuffer: pre,
            roiRect: roiRect
        )
        
        let fast9Input = (srScale > 1.0 ? srBuf : pre)
        
        // FAST9
        let raw = fast9Detect(fast9Input)
        
        // ROI buffers no longer needed
        yBuf.freeSelf()
        if var cb = cbBuf {
            cb.freeSelf()
        }
        
        // map to full frame
        let inv = 1.0 / CGFloat(srScale > 1.0 ? srScale : 1.0)
        
        var mapped: [CGPoint] = []
        mapped.reserveCapacity(raw.count)
        
        for rc in raw {
            let px = roiRect.origin.x + CGFloat(rc.x) * inv
            let py = roiRect.origin.y + CGFloat(rc.y) * inv
            mapped.append(CGPoint(x: px, y: py))
        }
        
        // VisionDots
        var vdots: [VisionDot] = []
        vdots.reserveCapacity(mapped.count)
        
        for (i,p) in mapped.enumerated() {
            vdots.append(
                VisionDot(id: i, position: p, score: raw[i].score, predicted: nil, velocity: nil)
            )
        }
        
        return (
            points: mapped,
            visionDots: vdots,
            preFast9: pre,
            srFast9: (srScale > 1.0 ? srBuf : nil)
        )
    }
}
