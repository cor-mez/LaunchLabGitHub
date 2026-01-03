//
//  ChromaDebugRenderer+Reuse.swift
//  LaunchLab
//
//  Reusable debug helpers for CbDebugRenderLoop
//

import Accelerate
import Metal

extension ChromaDebugRenderer {

    func makeCbTextureReused(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int,
        cache: inout vImage_Buffer?
    ) -> MTLTexture? {

        if cache == nil ||
           Int(cache!.width) != fullWidth ||
           Int(cache!.height) != fullHeight {

            cache?.freeSelf()
            cache = vImage_Buffer.makePlanar8(width: fullWidth, height: fullHeight)
        }

        guard var scaled = cache else { return nil }

        var src = cb
        vImageScale_Planar8(
            &src,
            &scaled,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        return makeTexture(fromPlanar8: scaled)
    }

    func makeNormalizedCbTextureReused(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int,
        scratch: inout vImage_Buffer?,
        scaledOut: inout vImage_Buffer?
    ) -> MTLTexture? {

        let w = Int(cb.width)
        let h = Int(cb.height)

        if scratch == nil ||
           scratch!.width != cb.width ||
           scratch!.height != cb.height {

            scratch?.freeSelf()
            scratch = vImage_Buffer.makePlanar8(width: w, height: h)
        }

        guard var norm = scratch else { return nil }

        let srcPtr = cb.data.assumingMemoryBound(to: UInt8.self)
        let rb = cb.rowBytes
        var minPx: UInt8 = 255
        var maxPx: UInt8 = 0

        for y in 0..<h {
            let row = srcPtr + y * rb
            for x in 0..<w {
                let px = row[x]
                minPx = min(minPx, px)
                maxPx = max(maxPx, px)
            }
        }

        let range = max(1, Int(maxPx) - Int(minPx))
        let dstPtr = norm.data.assumingMemoryBound(to: UInt8.self)

        for y in 0..<h {
            let srcRow = srcPtr + y * rb
            let dstRow = dstPtr + y * norm.rowBytes
            for x in 0..<w {
                let raw = srcRow[x]
                dstRow[x] = UInt8(clamping:
                    (Int(raw) - Int(minPx)) * 255 / range
                )
            }
        }

        if scaledOut == nil ||
           Int(scaledOut!.width) != fullWidth ||
           Int(scaledOut!.height) != fullHeight {

            scaledOut?.freeSelf()
            scaledOut = vImage_Buffer.makePlanar8(width: fullWidth, height: fullHeight)
        }

        guard var scaled = scaledOut else { return nil }

        var srcNorm = norm
        vImageScale_Planar8(
            &srcNorm,
            &scaled,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        return makeTexture(fromPlanar8: scaled)
    }
}
