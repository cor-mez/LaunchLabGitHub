// DebugProbe+Capture.swift
import CoreVideo

extension DebugProbe {

    static func probePixelBuffer(
        _ pb: CVPixelBuffer,
        phase: DebugPhase = .capture
    ) {
        guard isEnabled(phase) else { return }

        let fmt = CVPixelBufferGetPixelFormatType(pb)
        let planes = CVPixelBufferGetPlaneCount(pb)


        for i in 0..<planes {
            let w = CVPixelBufferGetWidthOfPlane(pb, i)
            let h = CVPixelBufferGetHeightOfPlane(pb, i)
           
        }
    }

    static func probeYPlaneBytes(
        _ pb: CVPixelBuffer,
        count: Int = 16,
        phase: DebugPhase = .capture
    ) {
        guard isEnabled(phase) else { return }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else {
            return
        }

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var bytes: [UInt8] = []

        for i in 0..<count {
            bytes.append(ptr[i])
        }
    }
}
