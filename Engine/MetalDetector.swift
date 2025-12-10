import Foundation
import CoreVideo
import Metal
import simd

final class MetalDetector {

    static let shared = MetalDetector()

    private let renderer = MetalRenderer.shared

    var fast9ThresholdY: Int = 20
    var fast9ThresholdCb: Int = 20

    var fast9ScoreMinY: Int = 12
    var fast9ScoreMinCb: Int = 12

    var nmsRadius: Int = 1
    var enableMasking: Bool = true

    private var cornerBufferY: UnsafeMutablePointer<UInt8>?
    private var scoreBufferY: UnsafeMutablePointer<Float>?

    private var cornerBufferCb: UnsafeMutablePointer<UInt8>?
    private var scoreBufferCb: UnsafeMutablePointer<Float>?

    struct DetectorTelemetry {
        let count: Int
        let meanScore: Float
        let minValue: Float
        let maxValue: Float
    }

    private init() {}

    private func allocateBuffers(width: Int, height: Int) {
        let count = width * height
        cornerBufferY?.deallocate()
        scoreBufferY?.deallocate()
        cornerBufferCb?.deallocate()
        scoreBufferCb?.deallocate()
        cornerBufferY = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        scoreBufferY = UnsafeMutablePointer<Float>.allocate(capacity: count)
        cornerBufferCb = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        scoreBufferCb = UnsafeMutablePointer<Float>.allocate(capacity: count)
    }

    private func applyScoreFilter(corners: [CGPoint],
                                  scores: UnsafeMutablePointer<Float>,
                                  width: Int) -> [CGPoint] {
        var out: [CGPoint] = []
        var idx = 0
        for p in corners {
            if scores[idx] >= Float(fast9ScoreMinY) {
                out.append(p)
            }
            idx += 1
        }
        return out
    }

    private func applyScoreFilterCb(corners: [CGPoint],
                                    scores: UnsafeMutablePointer<Float>,
                                    width: Int) -> [CGPoint] {
        var out: [CGPoint] = []
        var idx = 0
        for p in corners {
            if scores[idx] >= Float(fast9ScoreMinCb) {
                out.append(p)
            }
            idx += 1
        }
        return out
    }

    private func nms(_ corners: [CGPoint],
                     scores: UnsafeMutablePointer<Float>,
                     width: Int,
                     height: Int) -> [CGPoint] {
        let r = nmsRadius
        var suppressed = Set<Int>()
        var indexed: [(pt: CGPoint, idx: Int, score: Float)] = []
        var i = 0
        for p in corners {
            indexed.append((p, i, scores[i]))
            i += 1
        }
        indexed.sort { $0.score > $1.score }
        for entry in indexed {
            if suppressed.contains(entry.idx) { continue }
            let cx = Int(entry.pt.x)
            let cy = Int(entry.pt.y)
            for y in max(0, cy - r)...min(height - 1, cy + r) {
                for x in max(0, cx - r)...min(width - 1, cx + r) {
                    let id = y * width + x
                    if id != entry.idx {
                        suppressed.insert(id)
                    }
                }
            }
        }
        var out: [CGPoint] = []
        for entry in indexed {
            if suppressed.contains(entry.idx) == false {
                out.append(entry.pt)
            }
        }
        return out
    }

    private func maskCircle(_ corners: [CGPoint],
                            width: Int,
                            height: Int) -> [CGPoint] {
        if enableMasking == false { return corners }
        let cx = Float(width) * 0.5
        let cy = Float(height) * 0.5
        let r = min(cx, cy)
        let r2 = r * r
        var out: [CGPoint] = []
        for p in corners {
            let dx = Float(p.x) - cx
            let dy = Float(p.y) - cy
            if dx*dx + dy*dy <= r2 {
                out.append(p)
            }
        }
        return out
    }

    private func sortedCorners(_ corners: [CGPoint],
                               scores: UnsafeMutablePointer<Float>,
                               width: Int) -> [CGPoint] {
        var indexed: [(CGPoint, Float)] = []
        var idx = 0
        for p in corners {
            indexed.append((p, scores[idx]))
            idx += 1
        }
        indexed.sort { a, b in
            if a.1 == b.1 {
                if a.0.x == b.0.x { return a.0.y < b.0.y }
                return a.0.x < b.0.x
            }
            return a.1 > b.1
        }
        return indexed.map { $0.0 }
    }
}
extension MetalDetector {

    func prepareFrameY(_ pb: CVPixelBuffer,
                       roi: CGRect,
                       srScale: Float)
    {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        renderer.ensureFrameYSize(width: w, height: h)

        let rw = Int(roi.width)
        let rh = Int(roi.height)
        renderer.ensureRoiYSize(width: rw, height: rh)

        let srw = max(1, Int(Float(rw) * srScale))
        let srh = max(1, Int(Float(rh) * srScale))
        renderer.ensureSRYSize(width: srw, height: srh)

        allocateBuffers(width: srw, height: srh)

        let cb1 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.extractY(from: pb,
                                   into: renderer.textures.texY!,
                                   cb: cb1)
        cb1.commit()

        let cb2 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.cropY(from: renderer.textures.texY!,
                                into: renderer.textures.texYRoi!,
                                roiX: Int(roi.origin.x),
                                roiY: Int(roi.origin.y),
                                cb: cb2)
        cb2.commit()

        let minDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        minDesc.usage = [.shaderRead, .shaderWrite]
        let minTex = renderer.device.makeTexture(descriptor: minDesc)!

        let maxTex = renderer.device.makeTexture(descriptor: minDesc)!

        let cb3 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.reduceMinMax(of: renderer.textures.texYRoi!,
                                       minTex: minTex,
                                       maxTex: maxTex,
                                       cb: cb3)
        cb3.commit()

        let cb4 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.normalizeY(roi: renderer.textures.texYRoi!,
                                     into: renderer.textures.texYNorm!,
                                     minTex: minTex,
                                     maxTex: maxTex,
                                     cb: cb4)
        cb4.commit()

        let cb5 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.edgeY(norm: renderer.textures.texYNorm!,
                                into: renderer.textures.texYEdge!,
                                cb: cb5)
        cb5.commit()

        let cb6 = renderer.queue.makeCommandBuffer()!
        renderer.yCompute.upscaleY(from: renderer.textures.texYRoi!,
                                   into: renderer.textures.texYRoiSR!,
                                   scale: srScale,
                                   cb: cb6)
        cb6.commit()
    }

    func prepareFrameCb(_ pb: CVPixelBuffer,
                        roi: CGRect,
                        srScale: Float)
    {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        renderer.ensureFrameCbSize(width: w, height: h)

        let rw = Int(roi.width)
        let rh = Int(roi.height)
        renderer.ensureRoiCbSize(width: rw, height: rh)

        let srw = max(1, Int(Float(rw) * srScale))
        let srh = max(1, Int(Float(rh) * srScale))
        renderer.ensureSRCbSize(width: srw, height: srh)

        allocateBuffers(width: srw, height: srh)

        let cb1 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.extractCb(from: pb,
                                     into: renderer.textures.texCb!,
                                     cb: cb1)
        cb1.commit()

        let cb2 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.cropCb(from: renderer.textures.texCb!,
                                  into: renderer.textures.texCbRoi!,
                                  roiX: Int(roi.origin.x / 2),
                                  roiY: Int(roi.origin.y / 2),
                                  cb: cb2)
        cb2.commit()

        let minDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        minDesc.usage = [.shaderRead, .shaderWrite]
        let minTex = renderer.device.makeTexture(descriptor: minDesc)!

        let maxTex = renderer.device.makeTexture(descriptor: minDesc)!

        let cb3 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.reduceMinMax(of: renderer.textures.texCbRoi!,
                                        minTex: minTex,
                                        maxTex: maxTex,
                                        cb: cb3)
        cb3.commit()

        let cb4 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.normalizeCb(roi: renderer.textures.texCbRoi!,
                                       into: renderer.textures.texCbNorm!,
                                       minTex: minTex,
                                       maxTex: maxTex,
                                       cb: cb4)
        cb4.commit()

        let cb5 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.edgeCb(norm: renderer.textures.texCbNorm!,
                                  into: renderer.textures.texCbEdge!,
                                  cb: cb5)
        cb5.commit()

        let cb6 = renderer.queue.makeCommandBuffer()!
        renderer.cbCompute.upscaleCb(from: renderer.textures.texCbRoi!,
                                     into: renderer.textures.texCbRoiSR!,
                                     scale: srScale,
                                     cb: cb6)
        cb6.commit()
    }

    func gpuFast9CornersY() -> [CGPoint] {
        guard let src = renderer.textures.texYRoiSR,
              let dst = renderer.textures.texFast9Y,
              let score = renderer.textures.texFast9YScore else { return [] }

        let w = src.width
        let h = src.height

        let cb1 = renderer.queue.makeCommandBuffer()!
        renderer.fast9Compute.detectCorners(from: src,
                                            into: dst,
                                            threshold: fast9ThresholdY,
                                            cb: cb1)
        cb1.commit()
        cb1.waitUntilCompleted()

        let cb2 = renderer.queue.makeCommandBuffer()!
        renderer.fast9Compute.scoreCorners(from: src,
                                           into: score,
                                           threshold: fast9ThresholdY,
                                           cb: cb2)
        cb2.commit()
        cb2.waitUntilCompleted()

        renderer.fast9Compute.readBinaryFast9(from: dst,
                                              into: cornerBufferY!)
        renderer.fast9Compute.readScoreFast9(from: score,
                                             into: scoreBufferY!)

        var pts: [CGPoint] = []
        var idx = 0
        for y in 0..<h {
            for x in 0..<w {
                if cornerBufferY![idx] > 0 {
                    pts.append(CGPoint(x: x, y: y))
                }
                idx += 1
            }
        }
        return pts
    }

    func gpuFast9CornersCb() -> [CGPoint] {
        guard let src = renderer.textures.texCbRoiSR,
              let dst = renderer.textures.texFast9Cb,
              let score = renderer.textures.texFast9CbScore else { return [] }

        let w = src.width
        let h = src.height

        let cb1 = renderer.queue.makeCommandBuffer()!
        renderer.fast9Compute.detectCorners(from: src,
                                            into: dst,
                                            threshold: fast9ThresholdCb,
                                            cb: cb1)
        cb1.commit()
        cb1.waitUntilCompleted()

        let cb2 = renderer.queue.makeCommandBuffer()!
        renderer.fast9Compute.scoreCorners(from: src,
                                           into: score,
                                           threshold: fast9ThresholdCb,
                                           cb: cb2)
        cb2.commit()
        cb2.waitUntilCompleted()

        renderer.fast9Compute.readBinaryFast9(from: dst,
                                              into: cornerBufferCb!)
        renderer.fast9Compute.readScoreFast9(from: score,
                                             into: scoreBufferCb!)

        var pts: [CGPoint] = []
        var idx = 0
        for y in 0..<h {
            for x in 0..<w {
                if cornerBufferCb![idx] > 0 {
                    pts.append(CGPoint(x: x, y: y))
                }
                idx += 1
            }
        }
        return pts
    }
}
extension MetalDetector {

    func gpuFast9CornersYEnhanced() -> ([CGPoint], DetectorTelemetry) {
        guard let src = renderer.textures.texYRoiSR,
              let scoreBuf = scoreBufferY,
              let cornerBuf = cornerBufferY else {
            return ([], DetectorTelemetry(count: 0, meanScore: 0, minValue: 0, maxValue: 0))
        }

        let raw = gpuFast9CornersY()
        let w = src.width
        let h = src.height

        var idx = 0
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude
        var sum: Float = 0

        for _ in 0..<(w*h) {
            let sc = scoreBuf[idx]
            if sc < minV { minV = sc }
            if sc > maxV { maxV = sc }
            sum += sc
            idx += 1
        }

        let scoreFiltered = applyScoreFilter(corners: raw,
                                             scores: scoreBuf,
                                             width: w)
        let masked = maskCircle(scoreFiltered,
                                width: w,
                                height: h)
        let suppressed = nms(masked,
                             scores: scoreBuf,
                             width: w,
                             height: h)
        let sorted = sortedCorners(suppressed,
                                   scores: scoreBuf,
                                   width: w)

        let meanScore = sum / Float(w*h)
        let telemetry = DetectorTelemetry(count: sorted.count,
                                          meanScore: meanScore,
                                          minValue: minV,
                                          maxValue: maxV)
        return (sorted, telemetry)
    }

    func gpuFast9CornersCbEnhanced() -> ([CGPoint], DetectorTelemetry) {
        guard let src = renderer.textures.texCbRoiSR,
              let scoreBuf = scoreBufferCb,
              let cornerBuf = cornerBufferCb else {
            return ([], DetectorTelemetry(count: 0, meanScore: 0, minValue: 0, maxValue: 0))
        }

        let raw = gpuFast9CornersCb()
        let w = src.width
        let h = src.height

        var idx = 0
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude
        var sum: Float = 0

        for _ in 0..<(w*h) {
            let sc = scoreBuf[idx]
            if sc < minV { minV = sc }
            if sc > maxV { maxV = sc }
            sum += sc
            idx += 1
        }

        let scoreFiltered = applyScoreFilterCb(corners: raw,
                                               scores: scoreBuf,
                                               width: w)
        let masked = maskCircle(scoreFiltered,
                                width: w,
                                height: h)
        let suppressed = nms(masked,
                             scores: scoreBuf,
                             width: w,
                             height: h)
        let sorted = sortedCorners(suppressed,
                                   scores: scoreBuf,
                                   width: w)

        let meanScore = sum / Float(w*h)
        let telemetry = DetectorTelemetry(count: sorted.count,
                                          meanScore: meanScore,
                                          minValue: minV,
                                          maxValue: maxV)
        return (sorted, telemetry)
    }
}