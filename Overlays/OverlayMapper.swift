//
//  OverlayMapper.swift
//  LaunchLab
//

import UIKit
import AVFoundation

final class OverlayMapper {

    let bufferWidth: Int
    let bufferHeight: Int
    let previewLayer: AVCaptureVideoPreviewLayer
    let viewSize: CGSize          // ← ADD THIS

    init(
        bufferWidth: Int,
        bufferHeight: Int,
        viewSize: CGSize,         // ← ADD THIS PARAM
        previewLayer: AVCaptureVideoPreviewLayer
    ) {
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight
        self.viewSize = viewSize  // ← STORE IT
        self.previewLayer = previewLayer
    }

    // Convert pixel → view
    func mapCGPoint(_ p: CGPoint) -> CGPoint {
        let normalized = CGPoint(
            x: p.x / CGFloat(bufferWidth),
            y: p.y / CGFloat(bufferHeight)
        )
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalized)
    }

    func mapSIMD2(_ v: SIMD2<Float>) -> CGPoint {
        mapCGPoint(CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)))
    }

    func mapRowToViewY(_ r: CGFloat) -> CGFloat {
        let midPx = CGPoint(x: CGFloat(bufferWidth) * 0.5, y: r)
        return mapCGPoint(midPx).y
    }
}
