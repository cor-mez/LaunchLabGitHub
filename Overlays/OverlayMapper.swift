//
//  OverlayMapper.swift
//  LaunchLab
//
//  Unified coordinate-space mapper for all overlays.
//  Handles buffer→view transforms using the previewLayer’s
//  affine mapping. Production-safe.
//

import UIKit
import AVFoundation
import CoreGraphics

final class OverlayMapper {

    // ============================================================
    // MARK: - Stored Values
    // ============================================================

    /// Pixel buffer resolution
    let bufferWidth: Int
    let bufferHeight: Int

    /// The rendered view size
    let viewSize: CGSize

    /// The preview layer that performs the real transform
    private let previewLayer: AVCaptureVideoPreviewLayer

    // ============================================================
    // MARK: - Init
    // ============================================================

    init(
        bufferWidth: Int,
        bufferHeight: Int,
        viewSize: CGSize,
        previewLayer: AVCaptureVideoPreviewLayer
    ) {
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight
        self.viewSize = viewSize
        self.previewLayer = previewLayer
    }

    // ============================================================
    // MARK: - Core Mapping API
    // ============================================================

    /// Convert a CGPoint in pixel-buffer space → view coordinates.
    func mapPointFromBufferToView(point: CGPoint) -> CGPoint {

        // Preview layer uses normalized coordinates internally.
        // Convert buffer pixel → normalized (0–1)
        let nx = point.x / CGFloat(bufferWidth)
        let ny = point.y / CGFloat(bufferHeight)

        let normalized = CGPoint(x: nx, y: ny)

        // Convert via preview layer
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalized)
    }

    /// Convenience wrapper with full signature
    func mapPointFromBufferToView(
        point: CGPoint,
        bufferWidth: Int,
        bufferHeight: Int,
        viewSize: CGSize
    ) -> CGPoint {
        return mapPointFromBufferToView(point: point)
    }

    /// Convenience sync with older API
    func mapCGPoint(_ p: CGPoint) -> CGPoint {
        return mapPointFromBufferToView(point: p)
    }

    // ============================================================
    // MARK: - Row / Column Mapping Helpers
    // ============================================================

    /// Convert a pixel row → view Y coordinate.
    func mapRowToViewY(_ row: CGFloat) -> CGFloat {
        let p = CGPoint(x: CGFloat(bufferWidth) * 0.5, y: row)
        return mapPointFromBufferToView(point: p).y
    }

    /// Convert a (row, col) pixel location → view point.
    func mapPixelToView(row: CGFloat, col: CGFloat) -> CGPoint {
        return mapPointFromBufferToView(point: CGPoint(x: col, y: row))
    }

    // ============================================================
    // MARK: - Projected Points (RPE overlays)
    // ============================================================

    /// Map a SIMD2<Float> pixel coordinate → view space
    func mapSIMD2(_ p: SIMD2<Float>) -> CGPoint {
        let cg = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        return mapPointFromBufferToView(point: cg)
    }
}
