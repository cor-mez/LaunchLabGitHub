//
//  ShotDetector.swift
//  LaunchLab
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class ShotDetector: ObservableObject {

    static let shared = ShotDetector()

    @Published var shotDetected: Bool = false

    private var lastLoudTime: CFTimeInterval = 0
    private let threshold: Float = 0.18

    private init() {}

    func ingest(sampleBuffer: CMSampleBuffer) {

        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length: Int = 0
        var totalLength: Int = 0
        var p: UnsafeMutablePointer<Int8>? = nil

        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: &length,
            totalLengthOut: &totalLength,
            dataPointerOut: &p
        )

        guard status == kCMBlockBufferNoErr, let dataPointer = p else { return }

        let rms = Self.computeRMS(ptr: dataPointer, count: length)
        let now = CACurrentMediaTime()

        if rms > threshold && (now - lastLoudTime) > 0.25 {
            lastLoudTime = now
            shotDetected = true
        } else {
            shotDetected = false
        }
    }

    private static func computeRMS(ptr: UnsafePointer<Int8>, count: Int) -> Float {
        if count == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let v = Float(ptr[i]) / 127.0
            sum += v * v
        }
        return sqrt(sum / Float(count))
    }
}
