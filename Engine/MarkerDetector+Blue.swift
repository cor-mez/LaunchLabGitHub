//
//  MarkerDetector+Blue.swift
//  LaunchLab
//

import CoreGraphics
import CoreVideo

final class BlueDiamondDetector {

    func detect(
        in pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> [MarkerDetection] {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let cbBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return []
        }

        let cbWidth  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let cbHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let stride   = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        // Convert ROI into Cb plane coordinates
        let scaleX = CGFloat(cbWidth)  / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = CGFloat(cbHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let roiCb = CGRect(
            x: roi.origin.x * scaleX,
            y: roi.origin.y * scaleY,
            width: roi.width * scaleX,
            height: roi.height * scaleY
        )

        let ptr = cbBase.assumingMemoryBound(to: UInt8.self)

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: Int = 0

        // Tuned for Oracal Azure Blue + matte spray
        let threshold: UInt8 = 160

        let minX = max(0, Int(roiCb.minX))
        let maxX = min(cbWidth - 1, Int(roiCb.maxX))
        let minY = max(0, Int(roiCb.minY))
        let maxY = min(cbHeight - 1, Int(roiCb.maxY))

        for y in minY..<maxY {
            let row = y * stride
            for x in minX..<maxX {
                let v = ptr[row + x]
                if v > threshold {
                    sumX += CGFloat(x)
                    sumY += CGFloat(y)
                    count += 1
                }
            }
        }

        guard count > 40 else { return [] }

        let cxCb = sumX / CGFloat(count)
        let cyCb = sumY / CGFloat(count)

        let center = CGPoint(
            x: cxCb / scaleX,
            y: cyCb / scaleY
        )

        let sizePx = sqrt(CGFloat(count))
        let confidence = min(CGFloat(1.0), CGFloat(count) / 400.0)

        return [
            MarkerDetection(
                center: center,
                sizePx: sizePx,
                confidence: confidence
            )
        ]
    }
}
