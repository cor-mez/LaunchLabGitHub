import Foundation

struct CPUFast9NormalizedBuffer {
    let ptr: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
}

final class CPUFast9Normalizer {

    func normalize(buffer: UnsafeMutablePointer<UInt8>,
                   width: Int,
                   height: Int) -> CPUFast9NormalizedBuffer
    {
        let count = width * height

        var minV: UInt8 = 255
        var maxV: UInt8 = 0

        for i in 0..<count {
            let v = buffer[i]
            if v < minV { minV = v }
            if v > maxV { maxV = v }
        }

        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: count)

        let range = Float(maxV) - Float(minV)
        let inv = range > 0 ? 1.0 / range : 0.0

        for i in 0..<count {
            let v = Float(buffer[i])
            let nv = (v - Float(minV)) * inv
            let clamped = nv < 0 ? 0 : (nv > 1 ? 1 : nv)
            out[i] = UInt8(clamped * 255.0)
        }

        return CPUFast9NormalizedBuffer(ptr: out, width: width, height: height)
    }
}