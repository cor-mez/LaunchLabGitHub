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
    }

    static func probeDrawable(
        _ drawable: MTLDrawable?,
        size: CGSize,
        phase: DebugPhase = .preview
    ) {
        guard isEnabled(phase) else { return }
    }
}
