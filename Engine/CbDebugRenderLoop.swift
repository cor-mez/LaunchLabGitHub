//
//  CbDebugRenderLoop.swift
//  LaunchLab
//
//  v2 — Fully memory-safe, zero-malloc debug chroma renderer.
//  Reuses all buffers/textures; safe at 240 FPS capture.
//

import Foundation
import Metal
import Accelerate
import CoreVideo
import QuartzCore

final class CbDebugRenderLoop: ObservableObject {

    // MARK: - Published UI Textures (MainActor only)
    @MainActor @Published var yTexture: MTLTexture?
    @MainActor @Published var cbTexture: MTLTexture?
    @MainActor @Published var normTexture: MTLTexture?
    @MainActor @Published var zoomTextures: [MTLTexture]?

    // MARK: - Internal State
    private let chroma = ChromaDebugRenderer.shared
    private let queue  = DispatchQueue(label: "cb.debug.render.loop", qos: .userInitiated)

    private var lastNormUpdate: TimeInterval = 0
    private let normInterval: TimeInterval = 1.0 / 20.0

    // Cached buffers
    private var cbPlanarCache: vImage_Buffer?
    private var normPlanarCache: vImage_Buffer?
    private var scaledCbCache: vImage_Buffer?
    private var scaledNormCache: vImage_Buffer?

    private var zoom1Cache: vImage_Buffer?
    private var zoom2Cache: vImage_Buffer?
    private var zoom3Cache: vImage_Buffer?

    // MARK: - API

    func processFrame(
        pixelBuffer: CVPixelBuffer,
        showY: Bool,
        showCb: Bool,
        showNorm: Bool,
        roi: CGRect?
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let (yBuf, uvBuf) = self.extractPlanes(buf: pixelBuffer)
            let fullW = Int(yBuf.width)
            let fullH = Int(yBuf.height)

            let cbPlanar = self.extractCbPlanarReused(from: uvBuf)

            // Y
            if showY, let yTex = self.chroma.makeYTexture(from: pixelBuffer) {
                Task { @MainActor in self.yTexture = yTex }
            } else {
                Task { @MainActor in self.yTexture = nil }
            }

            // Cb
            if showCb,
               let cbTex = self.chroma.makeCbTextureReused(
                    from: cbPlanar,
                    fullWidth: fullW,
                    fullHeight: fullH,
                    cache: &self.scaledCbCache
               ) {
                Task { @MainActor in self.cbTexture = cbTex }
            } else {
                Task { @MainActor in self.cbTexture = nil }
            }

            // Normalized Cb (throttled)
            if showNorm {
                let now = CACurrentMediaTime()
                if now - self.lastNormUpdate >= self.normInterval {
                    self.lastNormUpdate = now
                    if let normTex = self.chroma.makeNormalizedCbTextureReused(
                        from: cbPlanar,
                        fullWidth: fullW,
                        fullHeight: fullH,
                        scratch: &self.normPlanarCache,
                        scaledOut: &self.scaledNormCache
                    ) {
                        Task { @MainActor in self.normTexture = normTex }
                    }
                }
            } else {
                Task { @MainActor in self.normTexture = nil }
            }

            // Zoom
            if let roi {
                let zooms = self.chroma.makeZoomLevelsReused(
                    from: cbPlanar,
                    fullWidth: fullW,
                    fullHeight: fullH,
                    roi: roi,
                    z1: &self.zoom1Cache,
                    z2: &self.zoom2Cache,
                    z3: &self.zoom3Cache
                )
                Task { @MainActor in self.zoomTextures = zooms }
            } else {
                Task { @MainActor in self.zoomTextures = nil }
            }
        }
    }

    // MARK: - Plane Extraction

    private func extractPlanes(buf: CVPixelBuffer)
    -> (y: vImage_Buffer, uv: vImage_Buffer) {

        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }

        let yBase = CVPixelBufferGetBaseAddressOfPlane(buf, 0)!
        let yBuf = vImage_Buffer(
            data: yBase,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(buf, 0)),
            width:  vImagePixelCount(CVPixelBufferGetWidthOfPlane(buf, 0)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buf, 0)
        )

        let uvBase = CVPixelBufferGetBaseAddressOfPlane(buf, 1)!
        let uvBuf = vImage_Buffer(
            data: uvBase,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(buf, 1)),
            width:  vImagePixelCount(CVPixelBufferGetWidthOfPlane(buf, 1)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buf, 1)
        )

        return (yBuf, uvBuf)
    }

    private func extractCbPlanarReused(from uv: vImage_Buffer) -> vImage_Buffer {
        let w = Int(uv.width)
        let h = Int(uv.height)

        if cbPlanarCache == nil ||
           cbPlanarCache!.width != uv.width ||
           cbPlanarCache!.height != uv.height {

            cbPlanarCache?.freeSelf()
            cbPlanarCache = vImage_Buffer.makePlanar8(width: w, height: h)
        }

        var out = cbPlanarCache!
        let src = uv.data.assumingMemoryBound(to: UInt8.self)
        let dst = out.data.assumingMemoryBound(to: UInt8.self)

        for y in 0..<h {
            let sRow = src + y * uv.rowBytes
            let dRow = dst + y * w
            for x in 0..<w {
                dRow[x] = sRow[x * 2]
            }
        }

        return out
    }
}
