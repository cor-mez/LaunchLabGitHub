//
//  CameraPreviewView.swift
//  LaunchLab
//

import SwiftUI
import AVFoundation
import UIKit

// -------------------------------------------------------------
// MARK: - UIView (Camera + Overlays)
// -------------------------------------------------------------
final class CameraPreviewUIView: UIView {

    // AV capture preview
    private let previewLayer = AVCaptureVideoPreviewLayer()

    // Overlays
    private let dotLayer = DotTrackingOverlayLayer()
    private let reprojLayer = ReprojectionOverlayLayer()
    private let poseLayer = PoseOverlayLayer()

    // Intrinsics provided externally
    private var intrinsics: CameraIntrinsics?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black

        // ----------------------------
        // Preview layer setup
        // ----------------------------
        previewLayer.videoGravity = .resizeAspect
        layer.addSublayer(previewLayer)

        // ----------------------------
        // Overlays
        // ----------------------------
        layer.addSublayer(dotLayer)
        layer.addSublayer(reprojLayer)
        layer.addSublayer(poseLayer)

        // ----------------------------
        // Bind to vision pipeline
        // ----------------------------
        VisionPipeline.shared.onFrame = { [weak self] frameData in
            guard let self = self else { return }

            let intr = self.intrinsics

            // Update overlays with model-1 pattern
            self.dotLayer.update(frame: frameData)
            self.reprojLayer.update(frame: frameData, intrinsics: intr)
            self.poseLayer.update(frame: frameData, intrinsics: intr)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // External setter — CameraManager should call this once intrinsics are known
    func setIntrinsics(_ intr: CameraIntrinsics) {
        self.intrinsics = intr
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer.frame = bounds
        dotLayer.frame = bounds
        reprojLayer.frame = bounds
        poseLayer.frame = bounds
    }

    // Provide camera session from outside
    func attachSession(_ session: AVCaptureSession) {
        previewLayer.session = session
    }
}


// -------------------------------------------------------------
// MARK: - SwiftUI Wrapper
// -------------------------------------------------------------
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession
    let intrinsics: CameraIntrinsics?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attachSession(session)

        if let intr = intrinsics {
            view.setIntrinsics(intr)
        }

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if let intr = intrinsics {
            uiView.setIntrinsics(intr)
        }
    }
}
