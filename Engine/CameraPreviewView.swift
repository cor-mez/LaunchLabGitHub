//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation

/// SwiftUI wrapper that owns a PreviewView (UIKit)
/// and syncs VisionPipeline → CALayer overlays.
struct CameraPreviewView: UIViewRepresentable {

    @EnvironmentObject private var camera: CameraManager
    @EnvironmentObject private var config: OverlayConfig   // overlay toggles

    let session: AVCaptureSession
    let intrinsics: CameraIntrinsics

    // ----------------------------------------------------------
    // MARK: - Coordinator
    // ----------------------------------------------------------
    class Coordinator {
        weak var preview: PreviewView?
        var overlays: [BaseOverlayLayer] = []

        func updateFrame(_ frame: VisionFrameData) {
            guard let preview = preview else { return }

            // Build mapper each frame (safe + cheap)
            let mapper = OverlayMapper(
                bufferWidth: frame.width,
                bufferHeight: frame.height,
                viewSize: preview.bounds.size,
                previewLayer: preview.videoPreviewLayer
            )

            // Push frame into overlays
            for layer in overlays {
                layer.assignMapper(mapper)
                layer.updateWithFrame(frame)
                DispatchQueue.main.async {
                    layer.setNeedsDisplay()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // ----------------------------------------------------------
    // MARK: - UIView creation
    // ----------------------------------------------------------
    func makeUIView(context: Context) -> PreviewView {
        let preview = PreviewView(session: session)

        preview.videoPreviewLayer.videoGravity = .resizeAspectFill
        preview.videoPreviewLayer.connection?.videoOrientation = .portrait

        context.coordinator.preview = preview

        // Install overlays based on config toggles
        let overlays = OverlayCoordinator.makeOverlays(config: config)
        preview.installOverlayLayers(overlays)
        context.coordinator.overlays = overlays

        return preview
    }

    // ----------------------------------------------------------
    // MARK: - UIView updates
    // ----------------------------------------------------------
    func updateUIView(_ preview: PreviewView, context: Context) {

        // Keep session updated
        preview.session = session

        // Rebuild overlays if toggles changed
        let overlays = OverlayCoordinator.makeOverlays(config: config)
        preview.installOverlayLayers(overlays)
        context.coordinator.overlays = overlays

        // Push latest frame
        if let frame = camera.latestFrame {
            context.coordinator.updateFrame(frame)
        }
    }
}
