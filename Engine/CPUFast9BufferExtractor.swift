import Foundation
import CoreVideo
import CoreGraphics

struct CPUFast9BufferExtractorResult {
    let ptr: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
}

final class CPUFast9BufferExtractor {

    func extractROI(pb: CVPixelBuffer, roi: CGRect) -> CPUFast9BufferExtractorResult {
        CVPixelBufferLockBaseAddress(pb, .readOnly)

        let fullW = CVPixelBufferGetWidth(pb)
        let bytes = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        let rx = Int(roi.origin.x)
        let ry = Int(roi.origin.y)
        let rw = Int(roi.width)
        let rh = Int(roi.height)

        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: rw * rh)

        var dstIndex = 0
        for y in 0..<rh {
            let sy = ry + y
            let srcRow = bytes + sy * bpr + rx
            memcpy(out + dstIndex, srcRow, rw)
            dstIndex += rw
        }

        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        return CPUFast9BufferExtractorResult(ptr: out, width: rw, height: rh)
    }
}