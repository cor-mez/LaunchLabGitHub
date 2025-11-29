// File: Engine/DotDetector.swift
//
//  DotDetector.swift
//  LaunchLab
//

import Foundation
import CoreGraphics
import CoreVideo
import Accelerate

final class DotDetector {

    private let responseThreshold: Float = 0.12
    private let maxPoints: Int = 256

    func detect(in pixelBuffer: CVPixelBuffer) -> [CGPoint] {
        let planeIndex = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)

        guard width > 8, height > 8 else { return [] }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex) else {
            return []
        }

        var src8 = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: rowBytes
        )

        let floatRowBytes = width * MemoryLayout<Float>.size
        let byteCount = floatRowBytes * height

        guard let srcFData = malloc(byteCount),
              let lapData = malloc(byteCount) else {
            return []
        }
        defer {
            free(srcFData)
            free(lapData)
        }

        var srcF = vImage_Buffer(
            data: srcFData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: floatRowBytes
        )

        var lapF = vImage_Buffer(
            data: lapData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: floatRowBytes
        )

        var scale: Float = 1.0 / 255.0
        var bias: Float = 0.0
        vImageConvert_Planar8toPlanarF(
            &src8,
            &srcF,
            scale,
            bias,
            vImage_Flags(kvImageNoFlags)
        )

        var blurKernel: [Float] = [
            1, 2, 1,
            2, 4, 2,
            1, 2, 1
        ]
        let blurDivisor: Int32 = 16

        blurKernel.withUnsafeMutableBufferPointer { kPtr in
            vImageConvolve_PlanarF(
                &srcF,
                &srcF,
                nil,
                0,
                0,
                kPtr.baseAddress,
                3,
                3,
                0,
                vImage_Flags(kvImageEdgeExtend)
            )
        }

        var lapKernel: [Float] = [
             0, -1,  0,
            -1,  4, -1,
             0, -1,  0
        ]
        _ = blurDivisor

        lapKernel.withUnsafeBufferPointer { kPtr in
            vImageConvolve_PlanarF(
                &srcF,
                &lapF,
                nil,
                0,
                0,
                kPtr.baseAddress,
                3,
                3,
                0,
                vImage_Flags(kvImageEdgeExtend)
            )
        }

        let stride = lapF.rowBytes / MemoryLayout<Float>.size
        let ptr = lapF.data.assumingMemoryBound(to: Float.self)

        var points: [CGPoint] = []
        points.reserveCapacity(128)

        let maxY = height - 1
        let maxX = width - 1

        for y in 1..<maxY {
            let rowOffset = y * stride
            for x in 1..<maxX {
                let idx = rowOffset + x
                let v = ptr[idx]

                if v < responseThreshold {
                    continue
                }

                let left      = ptr[idx - 1]
                let right     = ptr[idx + 1]
                let up        = ptr[idx - stride]
                let down      = ptr[idx + stride]
                let upLeft    = ptr[idx - stride - 1]
                let upRight   = ptr[idx - stride + 1]
                let downLeft  = ptr[idx + stride - 1]
                let downRight = ptr[idx + stride + 1]

                if v <= left || v <= right ||
                   v <= up   || v <= down  ||
                   v <= upLeft || v <= upRight ||
                   v <= downLeft || v <= downRight {
                    continue
                }

                points.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                if points.count >= maxPoints {
                    return points
                }
            }
        }

        return points
    }
}
