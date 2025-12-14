// DebugProbe+Metal.swift
import Metal

extension DebugProbe {

    static func probeTexture(
        _ tex: MTLTexture?,
        label: String,
        phase: DebugPhase = .preview
    ) {
        guard isEnabled(phase) else { return }

        guard let t = tex else {
           
            return
        }

        print(
            "[\(phase.rawValue.uppercased())]",
            label,
            "w:",
            t.width,
            "h:",
            t.height,
            "fmt:",
            t.pixelFormat.rawValue,
            "usage:",
            t.usage.rawValue
        )
    }

    static func probeDrawable(
        _ drawable: MTLDrawable?,
        size: CGSize,
        phase: DebugPhase = .preview
    ) {
        guard isEnabled(phase) else { return }

        print(
            "[\(phase.rawValue.uppercased())]",
            "drawable:",
            drawable != nil,
            "size:",
            size
        )
    }
}
