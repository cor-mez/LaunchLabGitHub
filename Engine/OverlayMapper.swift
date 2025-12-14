//
//  OverlayMapper.swift
//  LaunchLab
//

import UIKit
import AVFoundation

/// Converts camera pixel-space → UIView drawing coordinates.
/// Works with either:
///   • AVCaptureVideoPreviewLayer (main camera view)
///   • scaleAspectFit mapping (DotTestMode, where previewLayer=nil)
///
final class OverlayMapper {

    let bufferWidth: Int
    let bufferHeight: Int
    let viewSize: CGSize
    let previewLayer: AVCaptureVideoPreviewLayer?   // ← optional

    init(
        bufferWidth: Int,
        bufferHeight: Int,
        viewSize: CGSize,
        previewLayer: AVCaptureVideoPreviewLayer?
    ) {
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight
        self.viewSize = viewSize
        self.previewLayer = previewLayer
    }

    // MARK: - Public Mapping

    /// Pixel → View
    func mapCGPoint(_ p: CGPoint) -> CGPoint {
        // If previewLayer exists → use AVCaptureVideoPreviewLayer mapping
        if let pl = previewLayer {
            let normalized = CGPoint(
                x: p.x / CGFloat(bufferWidth),
                y: p.y / CGFloat(bufferHeight)
            )
            return pl.layerPointConverted(fromCaptureDevicePoint: normalized)
        }

        // Otherwise (DotTestMode) → scaleAspectFit mapping
        let scale = min(viewSize.width / CGFloat(bufferWidth),
                        viewSize.height / CGFloat(bufferHeight))

        let drawW = CGFloat(bufferWidth) * scale
        let drawH = CGFloat(bufferHeight) * scale

        let offsetX = (viewSize.width - drawW) * 0.5
        let offsetY = (viewSize.height - drawH) * 0.5

        let vx = offsetX + p.x * scale
        let vy = offsetY + p.y * scale
        return CGPoint(x: vx, y: vy)
    }

    func mapSIMD2(_ v: SIMD2<Float>) -> CGPoint {
        mapCGPoint(CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)))
    }

    func mapRowToViewY(_ r: CGFloat) -> CGFloat {
        let mid = CGPoint(x: CGFloat(bufferWidth) * 0.5, y: r)
        return mapCGPoint(mid).y
    }
}