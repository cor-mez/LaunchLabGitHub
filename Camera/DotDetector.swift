//
//  DotDetector.swift
//  LaunchLab
//
//  CPU FAST9 Detector with:
//   • 1/4-res FAST9
//   • Static elliptical ROI in lower-center (ball zone)
//   • Non-max suppression
//   • Max-corner limit = 24
//   • Full-res CGPoint output
//

import CoreVideo
import CoreGraphics
import Accelerate

final class DotDetector {

    // ------------------------------------------------------------
    // MARK: - FAST9 Pattern
    // ------------------------------------------------------------

    private static let circle: [(Int, Int)] = [
        (0, 3), (1, 3), (2, 2), (3, 1),
        (3, 0), (3,-1), (2,-2), (1,-3),
        (0,-3),(-1,-3),(-2,-2),(-3,-1),
        (-3, 0),(-3, 1),(-2, 2),(-1, 3)
    ]

    // ------------------------------------------------------------
    // MARK: - Tuned Parameters
    // ------------------------------------------------------------

    private let threshold: UInt8 = 22       // more forgiving than 28
    private let nmsRadius: Int = 4          // NMS suppression radius
    private let maxCorners = 24             // hard limit for stability
    private let ds = 4                      // downsample factor (1/4 res)

    // Elliptical ROI (full-res space):
    // centered at (width/2, height*0.65)
    // narrower in X to avoid net / edges
    private let roiRadiusX: CGFloat = 70   // horizontal radius
    private let roiRadiusY: CGFloat = 70   // vertical radius

    private var tmpCorners: [CGPoint] = []

    // ------------------------------------------------------------
    // MARK: - Public API
    // ------------------------------------------------------------

    /// Legacy entry point (no hint).
    func detect(in pixelBuffer: CVPixelBuffer) -> [CGPoint] {
        return detect(in: pixelBuffer, hintCenter: nil)
    }

    /// Main entry point: hintCenter is currently ignored.
    func detect(in pixelBuffer: CVPixelBuffer,
                hintCenter: CGPoint?) -> [CGPoint] {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return []
        }

        // Luma plane dimensions
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        // Downsampled grid
        let w = width  / ds
        let h = height / ds

        // Fixed ROI center in full-res space (lower-center)
        let cx = CGFloat(width)  / 2
        let cy = CGFloat(height) * 0.65

        let rx = roiRadiusX
        let ry = roiRadiusY
        let invRx2 = 1.0 / (rx * rx)
        let invRy2 = 1.0 / (ry * ry)

        tmpCorners.removeAll(keepingCapacity: true)

        // --------------------------------------------------------
        // FAST9 within fixed elliptical ROI
        // --------------------------------------------------------
        for y in 3 ..< (h - 3) {
            for x in 3 ..< (w - 3) {

                let yy = y * ds
                let xx = x * ds

                // Elliptical ROI mask:
                // ((x-cx)^2 / rx^2) + ((y-cy)^2 / ry^2) <= 1
                let dx = CGFloat(xx) - cx
                let dy = CGFloat(yy) - cy
                let ellipse = dx*dx * invRx2 + dy*dy * invRy2
                if ellipse > 1.0 { continue }

                let p = pixel(base, xx, yy, stride)

                var brighter = 0
                var darker   = 0

                for (dxi, dyi) in Self.circle {
                    let px = xx + dxi * ds
                    let py = yy + dyi * ds
                    let v  = pixel(base, px, py, stride)

                    if v > p &+ threshold { brighter += 1 }
                    if v < p &- threshold { darker   += 1 }

                    if brighter >= 9 || darker >= 9 {
                        tmpCorners.append(CGPoint(x: CGFloat(xx), y: CGFloat(yy)))
                        break
                    }
                }
            }
        }

        if tmpCorners.isEmpty { return [] }

        let suppressed = nms(tmpCorners, radius: nmsRadius, max: maxCorners)
        return suppressed
    }

    // ------------------------------------------------------------
    // MARK: - Pixel Read
    // ------------------------------------------------------------

    @inline(__always)
    private func pixel(_ base: UnsafeRawPointer, _ x: Int, _ y: Int, _ stride: Int) -> UInt8 {
        base.load(fromByteOffset: y * stride + x, as: UInt8.self)
    }

    // ------------------------------------------------------------
    // MARK: - NMS
    // ------------------------------------------------------------

    private func nms(_ pts: [CGPoint], radius: Int, max: Int) -> [CGPoint] {

        if pts.count <= 1 { return pts }

        let sorted = pts.sorted { $0.y < $1.y }
        var keep: [CGPoint] = []
        keep.reserveCapacity(max)

        for p in sorted {
            var suppressed = false

            for k in keep {
                if abs(k.x - p.x) < CGFloat(radius) &&
                   abs(k.y - p.y) < CGFloat(radius) {
                    suppressed = true
                    break
                }
            }

            if !suppressed {
                keep.append(p)
                if keep.count >= max { break }
            }
        }

        return keep
    }
}
