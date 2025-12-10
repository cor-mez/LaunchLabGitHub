// MetalDetector.swift

import Foundation
import CoreVideo
import CoreGraphics

final class MetalDetector {

    private let renderer = MetalCameraRenderer.shared

    private var fast9Y: [UInt8] = []
    private var fast9Cb: [UInt8] = []

    private var widthY: Int = 0
    private var heightY: Int = 0

    private var widthCb: Int = 0
    private var heightCb: Int = 0

    private var frameW: Int = 0
    private var frameH: Int = 0

    private func allocY(_ w: Int, _ h: Int) {
        let count = w * h
        if fast9Y.count != count {
            fast9Y = Array(repeating: 0, count: count)
        }
    }

    private func allocCb(_ w: Int, _ h: Int) {
        let count = w * h
        if fast9Cb.count != count {
            fast9Cb = Array(repeating: 0, count: count)
        }
    }

    func prepareFrameY(
        _ pb: CVPixelBuffer,
        roi: CGRect,
        srScale: Float,
        threshold: Float
    ) {
        frameW = CVPixelBufferGetWidth(pb)
        frameH = CVPixelBufferGetHeight(pb)

        renderer.prepareFast9YMap(
            pixelBuffer: pb,
            roi: roi,
            srScale: srScale,
            threshold: threshold
        )

        let dims = renderer.fast9YDimensions()
        allocY(dims.width, dims.height)

        var w = 0
        var h = 0
        fast9Y.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress {
                renderer.readFast9YMap(
                    into: base,
                    maxCount: buf.count,
                    outWidth: &w,
                    outHeight: &h
                )
            }
        }

        widthY = w
        heightY = h
    }

    func gpuFast9CornersY() -> [CGPoint] {
        guard widthY > 0, heightY > 0 else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(256)

        let fw = CGFloat(frameW)
        let fh = CGFloat(frameH)
        let mw = CGFloat(widthY)
        let mh = CGFloat(heightY)

        for y in 0..<heightY {
            for x in 0..<widthY {
                if fast9Y[y * widthY + x] > 0 {
                    let px = CGFloat(x) * fw / mw
                    let py = CGFloat(y) * fh / mh
                    out.append(CGPoint(x: px, y: py))
                }
            }
        }
        return out
    }

    func prepareFrameCb(
        _ pb: CVPixelBuffer,
        roi: CGRect,
        srScale: Float,
        threshold: Float
    ) {
        frameW = CVPixelBufferGetWidth(pb)
        frameH = CVPixelBufferGetHeight(pb)

        renderer.prepareFast9CbMap(
            pixelBuffer: pb,
            roi: roi,
            srScale: srScale,
            threshold: threshold
        )

        let dims = renderer.fast9CbDimensions()
        allocCb(dims.width, dims.height)

        var w = 0
        var h = 0
        fast9Cb.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress {
                renderer.readFast9CbMap(
                    into: base,
                    maxCount: buf.count,
                    outWidth: &w,
                    outHeight: &h
                )
            }
        }

        widthCb = w
        heightCb = h
    }

    func gpuFast9CornersCb() -> [CGPoint] {
        guard widthCb > 0, heightCb > 0 else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(256)

        let fw = CGFloat(frameW)
        let fh = CGFloat(frameH)
        let mw = CGFloat(widthCb)
        let mh = CGFloat(heightCb)

        for y in 0..<heightCb {
            for x in 0..<widthCb {
                if fast9Cb[y * widthCb + x] > 0 {
                    let px = CGFloat(x) * fw / mw
                    let py = CGFloat(y) * fh / mh
                    out.append(CGPoint(x: px, y: py))
                }
            }
        }
        return out
    }
}
