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

        // Attach camera session
        view.attachSession(camera.captureSession)
        // Setup overlay mapper once we know buffer size
        camera.onFrameDimensionsChanged = { width, height in
            let mapper = OverlayMapper(
                bufferWidth: width,
                bufferHeight: height,
                viewSize: view.bounds.size,  
                previewLayer: view.previewLayer
            )

            dotLayer.assignMapper(mapper)
            trackingLayer?.assignMapper(mapper)
            reprojectionLayer?.assignMapper(mapper)
        }

        // Add overlays
        view.addOverlay(dotLayer)
        if let t = trackingLayer { view.addOverlay(t) }
        if let r = reprojectionLayer { view.addOverlay(r) }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}
