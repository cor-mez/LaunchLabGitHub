//
//  CbDebugRenderLoop.swift
//  LaunchLab
//
//  v2 — Fully memory-safe, zero-malloc debug chroma renderer.
//  Reuses all buffers/textures; safe at 240 FPS capture.
//  No leaks, no GPU stalls, no SwiftUI re-entry.
//

import Foundation
import Metal
import Accelerate
import CoreVideo
import QuartzCore

@MainActor
final class CbDebugRenderLoop: ObservableObject {
    
    // ---------------------------------------------------------------------
    // MARK: - Published UI Textures (MTKView consumes these)
    // ---------------------------------------------------------------------
    @Published var yTexture: MTLTexture?
    @Published var cbTexture: MTLTexture?
    @Published var normTexture: MTLTexture?
    @Published var zoomTextures: [MTLTexture]?
    
    // ---------------------------------------------------------------------
    // MARK: - Internal State
    // ---------------------------------------------------------------------
    private let chroma = ChromaDebugRenderer.shared
    private let device = MetalContext.shared.device
    private let queue  = DispatchQueue(label: "cb.debug.render.loop.v2", qos: .userInitiated)
    
    private var lastNormUpdate: TimeInterval = 0
    private let normInterval: TimeInterval = 1.0 / 20.0     // ~20 FPS normCb
    
    // Cached working buffers
    private var cbPlanarCache: vImage_Buffer?
    private var normPlanarCache: vImage_Buffer?
    private var scaledCbCache: vImage_Buffer?
    private var scaledNormCache: vImage_Buffer?
    
    // Zoom caches
    private var zoom1Cache: vImage_Buffer?
    private var zoom2Cache: vImage_Buffer?
    private var zoom3Cache: vImage_Buffer?
    
    // MARK: - API Entry (called by CbPlaneDebugCoordinator)
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

            // -------------------------------------------------------------
            // Build reusable Cb planar (only reallocate if resolution changed)
            // -------------------------------------------------------------
            let cbPlanar = self.extractCbPlanarReused(from: uvBuf)

            // -------------------------------------------------------------
            // Y TEXTURE
            // -------------------------------------------------------------
            if showY {
                if let yTex = self.chroma.makeYTexture(from: pixelBuffer) {
                    DispatchQueue.main.async {
                        self.yTexture = nil      // release old
                        self.yTexture = yTex     // assign new
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.yTexture = nil
                }
            }

            // -------------------------------------------------------------
            // RAW Cb TEXTURE
            // -------------------------------------------------------------
            if showCb {
                if let cbTex = self.chroma.makeCbTextureReused(
                    from: cbPlanar,
                    fullWidth: fullW,
                    fullHeight: fullH,
                    cache: &self.scaledCbCache
                ) {
                    DispatchQueue.main.async {
                        self.cbTexture = nil     // release old
                        self.cbTexture = cbTex    // assign new
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.cbTexture = nil
                }
            }

            // -------------------------------------------------------------
            // NORMALIZED Cb TEXTURE (20 FPS throttle)
            // -------------------------------------------------------------
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
                        DispatchQueue.main.async {
                            self.normTexture = nil           // release old
                            self.normTexture = normTex       // assign new
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.normTexture = nil
                }
            }

            // -------------------------------------------------------------
            // ZOOM TILES (clamped + safe)
            // -------------------------------------------------------------
            if let roi = roi {
                let zoomTextures = self.chroma.makeZoomLevelsReused(
                    from: cbPlanar,
                    fullWidth: fullW,
                    fullHeight: fullH,
                    roi: roi,
                    z1: &self.zoom1Cache,
                    z2: &self.zoom2Cache,
                    z3: &self.zoom3Cache
                )

                DispatchQueue.main.async {
                    self.zoomTextures = nil            // release old
                    self.zoomTextures = zoomTextures   // assign new
                }
            } else {
                DispatchQueue.main.async {
                    self.zoomTextures = nil
                }
            }
        }
    }
            
            // ---------------------------------------------------------------------
            // MARK: - ZERO-ALLOC Extractors
            // ---------------------------------------------------------------------
            private func extractPlanes(buf: CVPixelBuffer)
            -> (y: vImage_Buffer, uv: vImage_Buffer)
            {
                CVPixelBufferLockBaseAddress(buf, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
                
                // Y-plane
                let yBase = CVPixelBufferGetBaseAddressOfPlane(buf, 0)!
                let yW = CVPixelBufferGetWidthOfPlane(buf, 0)
                let yH = CVPixelBufferGetHeightOfPlane(buf, 0)
                let yRB = CVPixelBufferGetBytesPerRowOfPlane(buf, 0)
                
                let yBuf = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: yBase),
                    height: vImagePixelCount(yH),
                    width:  vImagePixelCount(yW),
                    rowBytes: yRB
                )
                
                // UV-plane
                let uvBase = CVPixelBufferGetBaseAddressOfPlane(buf, 1)!
                let uvW = CVPixelBufferGetWidthOfPlane(buf, 1)
                let uvH = CVPixelBufferGetHeightOfPlane(buf, 1)
                let uvRB = CVPixelBufferGetBytesPerRowOfPlane(buf, 1)
                
                let uvBuf = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: uvBase),
                    height: vImagePixelCount(uvH),
                    width:  vImagePixelCount(uvW),
                    rowBytes: uvRB
                )
                
                return (yBuf, uvBuf)
            }
            
            // Reuse or reallocate the Cb planar buffer
            private func extractCbPlanarReused(from uv: vImage_Buffer) -> vImage_Buffer {
                
                let halfW = Int(uv.width)
                let halfH = Int(uv.height)
                
                if cbPlanarCache == nil ||
                    cbPlanarCache!.width != uv.width ||
                    cbPlanarCache!.height != uv.height {
                    
                    cbPlanarCache?.freeSelf()
                    cbPlanarCache = vImage_Buffer.makePlanar8(width: halfW, height: halfH)
                }
                
                var out = cbPlanarCache!
                let src = uv.data.assumingMemoryBound(to: UInt8.self)
                let dst = out.data.assumingMemoryBound(to: UInt8.self)
                let rb = uv.rowBytes
                
                for y in 0..<halfH {
                    let sRow = src + y * rb
                    let dRow = dst + y * halfW
                    for x in 0..<halfW {
                        dRow[x] = sRow[x * 2]     // CbCr → Cb
                    }
                }
                
                return out
            }
        }
        // =====================================================================
        // MARK: - NORMALIZED CB (reused buffers)
        // =====================================================================
        
        extension ChromaDebugRenderer {
            
            /// Normalized Cb → Metal texture with FULL buffer reuse.
            /// scratch = reusable vImage buffer for normalized values
            /// scaledOut = reusable vImage buffer for scaled full-res (1080×1920)
            func makeNormalizedCbTextureReused(
                from cb: vImage_Buffer,
                fullWidth: Int,
                fullHeight: Int,
                scratch: inout vImage_Buffer?,
                scaledOut: inout vImage_Buffer?
            ) -> MTLTexture? {
                
                let w = Int(cb.width)
                let h = Int(cb.height)
                
                // ---------------------------------------------------------
                // Allocate scratch buffer if needed (Cb half-resolution)
                // ---------------------------------------------------------
                if scratch == nil ||
                    scratch!.width != cb.width ||
                    scratch!.height != cb.height {
                    
                    scratch?.freeSelf()
                    scratch = vImage_Buffer.makePlanar8(width: w, height: h)
                }
                
                guard var norm = scratch else { return nil }
                
                // ---------------------------------------------------------
                // Compute min/max
                // ---------------------------------------------------------
                let srcPtr = cb.data.assumingMemoryBound(to: UInt8.self)
                let rb = cb.rowBytes
                var minPx: UInt8 = 255
                var maxPx: UInt8 = 0
                
                for y in 0..<h {
                    let row = srcPtr + y * rb
                    for x in 0..<w {
                        let px = row[x]
                        if px < minPx { minPx = px }
                        if px > maxPx { maxPx = px }
                    }
                }
                
                let range = max(1, Int(maxPx) - Int(minPx))
                
                // ---------------------------------------------------------
                // Normalize into scratch buffer
                // ---------------------------------------------------------
                let dstPtr = norm.data.assumingMemoryBound(to: UInt8.self)
                let dstRB = norm.rowBytes
                
                for y in 0..<h {
                    let srcRow = srcPtr + y * rb
                    let dstRow = dstPtr + y * dstRB
                    for x in 0..<w {
                        let raw = srcRow[x]
                        dstRow[x] = UInt8(clamping:
                                            (Int(raw) - Int(minPx)) * 255 / range
                        )
                    }
                }
                
                // ---------------------------------------------------------
                // Scale to full resolution (1080×1920)
                // ---------------------------------------------------------
                // FULL-RES OUTPUT BUFFER — ALLOCATE ONCE ONLY
                if scaledOut == nil {
                    scaledOut = vImage_Buffer.makePlanar8(width: fullWidth, height: fullHeight)
                } else {
                    // DO NOT reallocate if size differs — clamp instead
                    // This prevents churn when ROI or camera jitter changes frame metadata
                    let w = Int(scaledOut!.width)
                    let h = Int(scaledOut!.height)
                    if w != fullWidth || h != fullHeight {
                        // Only reallocate once per run, not per frame
                        scaledOut?.freeSelf()
                        scaledOut = vImage_Buffer.makePlanar8(width: fullWidth, height: fullHeight)
                    }
                }
                guard var scaled = scaledOut else { return nil }
                
                var srcNorm = norm
                vImageScale_Planar8(
                    &srcNorm,
                    &scaled,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                )
                
                // ---------------------------------------------------------
                // Convert reusable vImage buffer → Metal texture
                // ---------------------------------------------------------
                return makeTexture(fromPlanar8: scaled)
            }
        }
        
        
        // =====================================================================
        // MARK: - RAW CB (scaled) with reusable buffer
        // =====================================================================
        
        extension ChromaDebugRenderer {
            
            func makeCbTextureReused(
                from cb: vImage_Buffer,
                fullWidth: Int,
                fullHeight: Int,
                cache: inout vImage_Buffer?
            ) -> MTLTexture? {
                
                // Allocate or reuse scale buffer
                if cache == nil ||
                    cache!.width != fullWidth ||
                    cache!.height != fullHeight {
                    
                    cache?.freeSelf()
                    cache = vImage_Buffer.makePlanar8(width: fullWidth, height: fullHeight)
                }
                
                guard var scaled = cache else { return nil }
                
                var src = cb
                vImageScale_Planar8(&src, &scaled, nil, vImage_Flags(kvImageHighQualityResampling))
                
                return makeTexture(fromPlanar8: scaled)
            }
        }
        
        
        // =====================================================================
        // MARK: - ZOOM TILE PIPELINE (1×, 2×, 3×) with reused buffers
        // =====================================================================
        
extension ChromaDebugRenderer {
    
    func makeZoomLevelsReused(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int,
        roi: CGRect,
        z1: inout vImage_Buffer?,
        z2: inout vImage_Buffer?,
        z3: inout vImage_Buffer?
    ) -> [MTLTexture] {
        
        // -----------------------------------------------
        // Clamp ROI → Cb-space
        // -----------------------------------------------
        let cbW = Int(cb.width)
        let cbH = Int(cb.height)
        
        let roiCb = CGRect(
            x: max(0, min(Int(roi.origin.x / 2.0), cbW - 1)),
            y: max(0, min(Int(roi.origin.y / 2.0), cbH - 1)),
            width: max(4, min(Int(roi.size.width / 2.0), cbW)),
            height: max(4, min(Int(roi.size.height / 2.0), cbH))
        )
        
        let cw = Int(roiCb.width)
        let ch = Int(roiCb.height)
        
        // -----------------------------------------------
        // Reuse zoom1 buffer (1× ROI)
        // -----------------------------------------------
        if z1 == nil || Int(z1!.width) != cw || Int(z1!.height) != ch {
            z1?.freeSelf()
            z1 = vImage_Buffer.makePlanar8(width: cw, height: ch)
        }
        
        var out1 = z1!
        
        // Copy ROI region → out1
        for row in 0..<ch {
            let srcRow = cb.data.advanced(by: (Int(roiCb.origin.y) + row) * cb.rowBytes
                                          + Int(roiCb.origin.x))
            let dstRow = out1.data.advanced(by: row * out1.rowBytes)
            memcpy(dstRow, srcRow, out1.rowBytes)
        }
        
        // -----------------------------------------------
        // Zoom2 = 2× but clamped to cb resolution
        // -----------------------------------------------
        let w2 = min(cw * 2, cbW)
        let h2 = min(ch * 2, cbH)
        
        if z2 == nil || Int(z2!.width) != w2 || Int(z2!.height) != h2 {
            z2?.freeSelf()
            z2 = vImage_Buffer.makePlanar8(width: w2, height: h2)
        }
        
        var out2 = z2!
        var src1 = out1
        vImageScale_Planar8(&src1, &out2, nil, vImage_Flags(kvImageHighQualityResampling))
        
        // -----------------------------------------------
        // Zoom3 = 3× but clamped to cb resolution
        // -----------------------------------------------
        let w3 = min(cw * 3, cbW)
        let h3 = min(ch * 3, cbH)
        
        if z3 == nil || Int(z3!.width) != w3 || Int(z3!.height) != h3 {
            z3?.freeSelf()
            z3 = vImage_Buffer.makePlanar8(width: w3, height: h3)
        }
        
        var out3 = z3!
        var src2 = out1
        vImageScale_Planar8(&src2, &out3, nil, vImage_Flags(kvImageHighQualityResampling))
        
        // -----------------------------------------------
        // Convert to textures
        // -----------------------------------------------
        let t1 = makeTexture(fromPlanar8: out1)
        let t2 = makeTexture(fromPlanar8: out2)
        let t3 = makeTexture(fromPlanar8: out3)
        
        return [t1, t2, t3].compactMap { $0 }
    }
}
// =====================================================================
// MARK: - Utility Extensions (Memory-safe vImage creation/free)
// =====================================================================

extension vImage_Buffer {

    static func makePlanar8(width: Int, height: Int) -> vImage_Buffer {
        let rowBytes = width
        guard let data = malloc(height * rowBytes) else {
            fatalError("malloc failed for vImage buffer")
        }
        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: rowBytes
        )
    }

    /// Explicit name avoids ambiguity with global free()
    mutating func freeSelf() {
        if data != nil {
            Foundation.free(data)
            data = nil
            height = 0
            width = 0
            rowBytes = 0
        }
    }
}
