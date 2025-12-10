import Foundation
import simd
import CoreGraphics

final class CPUFast9 {

    let threshold: Int

    private let circleX: [Int] = [0,1,2,3,3,3,2,1,0,-1,-2,-3,-3,-3,-2,-1]
    private let circleY: [Int] = [-3,-3,-2,-1,0,1,2,3,3,3,2,1,0,-1,-2,-3]

    init(threshold: Int = 20) {
        self.threshold = threshold
    }

    func detectCorners(src: UnsafePointer<UInt8>,
                       width: Int,
                       height: Int) -> [CGPoint]
    {
        var out: [CGPoint] = []

        for y in 3..<(height-3) {
            for x in 3..<(width-3) {

                let center = Int(src[y*width + x])
                var count = 0

                for i in 0..<16 {
                    let xx = x + circleX[i]
                    let yy = y + circleY[i]
                    let v = Int(src[yy*width + xx])
                    if abs(v - center) > threshold { count += 1 }
                }

                if count > 9 {
                    out.append(CGPoint(x: x, y: y))
                }
            }
        }

        return out
    }

    func scoreCorners(src: UnsafePointer<UInt8>,
                      width: Int,
                      height: Int) -> ([CGPoint], [UInt8])
    {
        var pts: [CGPoint] = []
        var scores = [UInt8](repeating: 0, count: width * height)

        for y in 3..<(height-3) {
            for x in 3..<(width-3) {

                let center = Int(src[y*width + x])
                var sc = 0

                for i in 0..<16 {
                    let xx = x + circleX[i]
                    let yy = y + circleY[i]
                    let v = Int(src[yy*width + xx])
                    if abs(v - center) > threshold { sc += 1 }
                }

                if sc > 9 {
                    pts.append(CGPoint(x: x, y: y))
                }
                scores[y*width + x] = UInt8(min(sc, 255))
            }
        }

        return (pts, scores)
    }

    func detectAndScore(src: UnsafePointer<UInt8>,
                        width: Int,
                        height: Int) -> ([CGPoint], [UInt8])
    {
        return scoreCorners(src: src, width: width, height: height)
    }
}   