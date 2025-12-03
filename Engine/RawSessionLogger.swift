// File: Engine/RawSessionLogger.swift
//
//  RawSessionLogger.swift
//  LaunchLab
//

import Foundation
import CoreVideo
import simd
import CoreGraphics

final class RawSessionLogger {

    private var writer: RawSessionWriter?
    private var isRecording: Bool = false
    private var sessionStartTime: Double = 0
    private var frameIndex: Int = 0
    private var lastStateCode: Int = 0

    private let maxDuration: Double = 10.0

    init() {}

    func start(timestamp: Double) {
        guard !isRecording else { return }
        guard let sessionDirectory = Self.makeSessionDirectory() else { return }

        writer = RawSessionWriter(sessionDirectory: sessionDirectory)
        guard writer != nil else { return }

        isRecording = true
        sessionStartTime = timestamp
        frameIndex = 0
    }

    func stop() {
        isRecording = false
        writer = nil
    }

    func handleFrame(
        frame: VisionFrameData,
        imu: IMUState,
        intrinsics: CameraIntrinsics,
        exposureISO: Float,
        exposureDuration: Double,
        unsafeLighting: Bool,
        unsafeFrameRate: Bool,
        unsafeThermal: Bool
    ) {
        let timestamp = frame.timestamp
        let residuals = frame.residuals ?? []

        let ballLock = Self.extractBallLock(from: residuals)
        let stateCode = ballLock?.stateCode ?? 0

        if !isRecording && stateCode == 1 && lastStateCode != 1 {
            start(timestamp: timestamp)
        }

        if isRecording {
            let elapsed = timestamp - sessionStartTime
            if stateCode == 3 || elapsed > maxDuration {
                stop()
            }
        }

        if isRecording, let writer = writer {
            frameIndex &+= 1

            let rs = Self.extractRS(from: residuals)
            let flicker = Self.extractFlicker(from: residuals)

            let dots = frame.dots.map {
                RawSessionDot(
                    x: Float($0.position.x),
                    y: Float($0.position.y)
                )
            }

            let residualLogs: [RawSessionResidual] = residuals.map {
                RawSessionResidual(
                    id: $0.id,
                    ex: $0.error.x,
                    ey: $0.error.y,
                    weight: $0.weight
                )
            }

            let intrDTO = RawSessionIntrinsics(
                fx: intrinsics.fx,
                fy: intrinsics.fy,
                cx: intrinsics.cx,
                cy: intrinsics.cy
            )

            let gravity = imu.gravity
            let rotationRate = imu.rotationRate
            let q = imu.attitude.vector

            let entry = RawSessionEntry(
                frameIndex: frameIndex,
                timestamp: timestamp,
                intrinsics: intrDTO,
                imuGravity: [gravity.x, gravity.y, gravity.z],
                imuRotationRate: [rotationRate.x, rotationRate.y, rotationRate.z],
                imuAttitude: [q.x, q.y, q.z, q.w],
                iso: exposureISO,
                exposureDuration: exposureDuration,
                ballRadiusPx: nil,
                ballLockState: ballLock?.stateCode,
                ballLockQuality: ballLock?.quality,
                rsShear: rs?.shear,
                rsRowSpan: rs?.rowSpan,
                rsConfidence: rs?.confidence,
                flickerModulation: flicker,
                unsafeLighting: unsafeLighting,
                unsafeFrameRate: unsafeFrameRate,
                unsafeThermal: unsafeThermal,
                dots: dots,
                residuals: residualLogs
            )

            if let yData = Self.extractYPlaneData(from: frame.pixelBuffer) {
                writer.write(
                    frameIndex: frameIndex,
                    yData: yData,
                    telemetry: entry
                )
            }
        }

        lastStateCode = stateCode
    }

    // MARK: - Helpers

    private static func makeSessionDirectory() -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let sessionsRoot = docs.appendingPathComponent("Sessions", isDirectory: true)
        if !fm.fileExists(atPath: sessionsRoot.path) {
            try? fm.createDirectory(at: sessionsRoot, withIntermediateDirectories: true, attributes: nil)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = formatter.string(from: Date())

        let dir = sessionsRoot.appendingPathComponent(name, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }

        return dir
    }

    private static func extractYPlaneData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let planeIndex = 0
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)

        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex) else {
            return nil
        }

        let byteCount = rowBytes * height
        return Data(bytes: base, count: byteCount)
    }

    private static func extractBallLock(
        from residuals: [RPEResidual]
    ) -> (stateCode: Int, quality: Float)? {
        guard let r = residuals.first(where: { $0.id == 101 }) else {
            return nil
        }
        let quality = r.error.x
        let stateCode = Int(r.error.y.rounded())
        return (stateCode: stateCode, quality: quality)
    }

    private static func extractRS(
        from residuals: [RPEResidual]
    ) -> (shear: Float, rowSpan: Float, confidence: Float)? {
        guard let r = residuals.first(where: { $0.id == 104 }) else {
            return nil
        }
        let shear = r.error.x
        let rowSpan = r.error.y
        let confidence = r.weight
        return (shear: shear, rowSpan: rowSpan, confidence: confidence)
    }

    private static func extractFlicker(
        from residuals: [RPEResidual]
    ) -> Float? {
        guard let r = residuals.first(where: { $0.id == 105 }) else {
            return nil
        }
        return r.error.y
    }
}
