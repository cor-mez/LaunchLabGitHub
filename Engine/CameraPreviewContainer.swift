//
//  CameraPreviewContainer.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

struct CameraPreviewContainer: UIViewRepresentable {

    @ObservedObject var camera: CameraManager
    let dotLayer: DotOverlayLayer
    let trackingLayer: DotTrackingOverlayLayer?
    let reprojectionLayer: ReprojectionOverlayLayer?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()

        // ---------------------------------------------------------
        // Attach live camera session (always from MAIN thread)
        // ---------------------------------------------------------
        DispatchQueue.main.async {
            view.attachSession(camera.captureSession)
        }

        // ---------------------------------------------------------
        // Buffer dimension callback → update overlay mappers
        // ---------------------------------------------------------
        camera.onFrameDimensionsChanged = { width, height in
            DispatchQueue.main.async {
                // Reattach session on dimension change (safe no-op)
                view.attachSession(camera.captureSession)

                // Build new mapper for updated buffer size
                let mapper = OverlayMapper(
                    bufferWidth: width,
                    bufferHeight: height,
                    viewSize: view.bounds.size,
                    previewLayer: view.previewLayer
                )

                dotLayer.assignMapper(mapper)
                trackingLayer?.assignMapper(mapper)
                reprojectionLayer?.assignMapper(mapper)

                // Force overlays to redraw
                dotLayer.setNeedsDisplay()
                trackingLayer?.setNeedsDisplay()
                reprojectionLayer?.setNeedsDisplay()
            }
        }

        // ---------------------------------------------------------
        // Install overlay layers (must be done AFTER session attach)
        // ---------------------------------------------------------
        view.addOverlay(dotLayer)
        if let t = trackingLayer { view.addOverlay(t) }
        if let r = reprojectionLayer { view.addOverlay(r) }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // No-op. Updates come from mapper + layer.setNeedsDisplay()
    }
}
