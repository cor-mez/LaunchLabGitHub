//
//  CameraRegimeObserver.swift
//  LaunchLab
//
//  Observes global photometric instability.
//  Observational only.
//

import CoreVideo

final class CameraRegimeObserver {

    private var lastMeanLuma: Double?
    private let maxDeltaLuma: Double = 8.0

    private(set) var isStable: Bool = true

    func reset() {
        lastMeanLuma = nil
        isStable = true
    }

    func observe(pixelBuffer: CVPixelBuffer) {

        let mean = computeMeanLuma(pb: pixelBuffer)

        if let last = lastMeanLuma {
            let delta = abs(mean - last)
            if delta > maxDeltaLuma {
                isStable = false
            }
        }

        lastMeanLuma = mean
    }

    private func computeMeanLuma(pb: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0 }

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        var sum: UInt64 = 0
        var count: UInt64 = 0

        for y in stride(from: 0, to: height, by: 4) {
            let row = base.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: 4) {
                let luma = row.load(fromByteOffset: x, as: UInt8.self)
                sum += UInt64(luma)
                count += 1
            }
        }

        return count > 0 ? Double(sum) / Double(count) : 0
    }
}
