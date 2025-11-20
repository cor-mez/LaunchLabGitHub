//
//  RSTimingCalibrator.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd

public struct RSTimingSample {
    public let frameTimestamp: Float
    public let barRow: Float
}

public final class RSTimingCalibrator {

    private var samples: [RSTimingSample] = []
    private let minLuma: UInt8 = 180

    public init() {}

    public func reset() {
        samples.removeAll()
    }

    public func addFrame(pixelBuffer: CVPixelBuffer, timestamp: Float) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var bestRow: Int = -1
        var maxL: UInt8 = 0

        for y in 0..<height {
            let rowPtr = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            let sumL = sumRow(rowPtr, count: width)
            if sumL > maxL {
                maxL = sumL
                bestRow = y
            }
        }

        if bestRow >= 0 && maxL >= minLuma {
            samples.append(RSTimingSample(frameTimestamp: timestamp,
                                          barRow: Float(bestRow)))
        }
    }

    private func sumRow(_ ptr: UnsafePointer<UInt8>, count: Int) -> UInt8 {
        var maxV: UInt8 = 0
        for i in stride(from: 0, to: count, by: 8) {
            let v = ptr[i]
            if v > maxV { maxV = v }
        }
        return maxV
    }

    public func fitModel() -> RSTimingCalibratedModel {
        guard !samples.isEmpty else {
            return RSTimingCalibratedModel(readout: 0.0039, curve: [0,1])
        }

        var minRow: Float = .greatestFiniteMagnitude
        var maxRow: Float = 0

        for s in samples {
            if s.barRow < minRow { minRow = s.barRow }
            if s.barRow > maxRow { maxRow = s.barRow }
        }

        let heightRange = max(1, maxRow - minRow)
        let normalized = samples.map { ($0.barRow - minRow) / heightRange }

        let sorted = normalized.sorted()
        return RSTimingCalibratedModel(readout: 0.0039,
                                       curve: sorted)
    }
}