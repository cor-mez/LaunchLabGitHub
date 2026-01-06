//
//  BlobDetector.swift
//  LaunchLab
//
//  Luma-based blob detector for ball presence.
//  OBSERVATIONAL ONLY — no authority.
//

import CoreGraphics
import CoreVideo

struct Blob {
    let center: CGPoint
    let area: Int
    let radius: CGFloat
    let compactness: Double
}

final class BlobDetector {

    // Tuned conservatively for white golf ball
    private let minLuma: UInt8 = 190
    private let minArea: Int = 80
    private let maxArea: Int = 2000

    func detect(
        pixelBuffer: CVPixelBuffer,
        roi: CGRect
    ) -> Blob? {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let ox = Int(roi.origin.x)
        let oy = Int(roi.origin.y)
        let rw = Int(roi.width)
        let rh = Int(roi.height)

        var points: [CGPoint] = []

        for y in 0..<rh {
            let row = base.advanced(by: (oy + y) * bytesPerRow)
            for x in 0..<rw {
                let v = row.load(fromByteOffset: ox + x, as: UInt8.self)
                if v >= minLuma {
                    points.append(CGPoint(x: ox + x, y: oy + y))
                }
            }
        }

        guard points.count >= minArea, points.count <= maxArea else {
            return nil
        }

        // Centroid
        let sum = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }

        let center = CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )

        // Radius estimate
        var maxD: CGFloat = 0
        for p in points {
            let dx = p.x - center.x
            let dy = p.y - center.y
            maxD = max(maxD, hypot(dx, dy))
        }

        let area = points.count
        let circleArea = Double.pi * Double(maxD * maxD)
        let compactness = Double(area) / max(circleArea, 1.0)

        guard compactness >= 0.35 else { return nil }

        return Blob(
            center: center,
            area: area,
            radius: maxD,
            compactness: compactness
        )
    }
}
