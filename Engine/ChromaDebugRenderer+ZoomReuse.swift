//
//  ChromaDebugRenderer+ZoomReuse.swift
//  LaunchLab
//
//  Reused zoom helpers for debug chroma rendering
//

import Accelerate
import CoreGraphics
import Metal

extension ChromaDebugRenderer {

    func makeZoomLevelsReused(
        from cb: vImage_Buffer,
        fullWidth: Int,
        fullHeight: Int,
        roi: CGRect,
        z1: inout vImage_Buffer?,
        z2: inout vImage_Buffer?,
        z3: inout vImage_Buffer?
    ) -> [MTLTexture]? {

        let cbW = Int(cb.width)
        let cbH = Int(cb.height)

        // Convert ROI → Cb space (half-res)
        let roiCb = CGRect(
            x: max(0, min(Int(roi.origin.x / 2.0), cbW - 1)),
            y: max(0, min(Int(roi.origin.y / 2.0), cbH - 1)),
            width: max(4, min(Int(roi.size.width / 2.0), cbW)),
            height: max(4, min(Int(roi.size.height / 2.0), cbH))
        )

        let cw = Int(roiCb.width)
        let ch = Int(roiCb.height)

        // -------------------------
        // Zoom 1×
        // -------------------------
        if z1 == nil || Int(z1!.width) != cw || Int(z1!.height) != ch {
            z1?.freeSelf()
            z1 = vImage_Buffer.makePlanar8(width: cw, height: ch)
        }

        var out1 = z1!
        for row in 0..<ch {
            let srcRow = cb.data.advanced(
                by: (Int(roiCb.origin.y) + row) * cb.rowBytes + Int(roiCb.origin.x)
            )
            let dstRow = out1.data.advanced(by: row * out1.rowBytes)
            memcpy(dstRow, srcRow, out1.rowBytes)
        }

        // -------------------------
        // Zoom 2×
        // -------------------------
        let w2 = min(cw * 2, cbW)
        let h2 = min(ch * 2, cbH)

        if z2 == nil || Int(z2!.width) != w2 || Int(z2!.height) != h2 {
            z2?.freeSelf()
            z2 = vImage_Buffer.makePlanar8(width: w2, height: h2)
        }

        var out2 = z2!
        var src1 = out1
        vImageScale_Planar8(
            &src1,
            &out2,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        // -------------------------
        // Zoom 3×
        // -------------------------
        let w3 = min(cw * 3, cbW)
        let h3 = min(ch * 3, cbH)

        if z3 == nil || Int(z3!.width) != w3 || Int(z3!.height) != h3 {
            z3?.freeSelf()
            z3 = vImage_Buffer.makePlanar8(width: w3, height: h3)
        }

        var out3 = z3!
        var src2 = out1
        vImageScale_Planar8(
            &src2,
            &out3,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        // -------------------------
        // Convert → Metal textures
        // -------------------------
        let t1 = makeTexture(fromPlanar8: out1)
        let t2 = makeTexture(fromPlanar8: out2)
        let t3 = makeTexture(fromPlanar8: out3)

        return [t1, t2, t3].compactMap { $0 }
    }
}
