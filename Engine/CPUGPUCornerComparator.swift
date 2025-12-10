import Foundation
import CoreGraphics

final class CPUGPUCornerComparator {

    struct Result {
        let matches: [CGPoint]
        let cpuOnly: [CGPoint]
        let gpuOnly: [CGPoint]
    }

    func compare(cpu: [CGPoint], gpu: [CGPoint]) -> Result {
        var cpuSet = Set<Int>()
        var gpuSet = Set<Int>()

        for p in cpu {
            let ix = Int(p.y) << 16 | Int(p.x)
            cpuSet.insert(ix)
        }

        for p in gpu {
            let ix = Int(p.y) << 16 | Int(p.x)
            gpuSet.insert(ix)
        }

        let matchIDs = cpuSet.intersection(gpuSet)
        let cpuOnlyIDs = cpuSet.subtracting(gpuSet)
        let gpuOnlyIDs = gpuSet.subtracting(cpuSet)

        var matches: [CGPoint] = []
        var cpuOnly: [CGPoint] = []
        var gpuOnly: [CGPoint] = []

        for id in matchIDs {
            let x = CGFloat(id & 0xFFFF)
            let y = CGFloat((id >> 16) & 0xFFFF)
            matches.append(CGPoint(x: x, y: y))
        }

        for id in cpuOnlyIDs {
            let x = CGFloat(id & 0xFFFF)
            let y = CGFloat((id >> 16) & 0xFFFF)
            cpuOnly.append(CGPoint(x: x, y: y))
        }

        for id in gpuOnlyIDs {
            let x = CGFloat(id & 0xFFFF)
            let y = CGFloat((id >> 16) & 0xFFFF)
            gpuOnly.append(CGPoint(x: x, y: y))
        }

        return Result(matches: matches,
                      cpuOnly: cpuOnly,
                      gpuOnly: gpuOnly)
    }
}