//
//  DotTestViewController.swift
//  LaunchLab
//
//  Camera preview + minimal ROI overlay box.
//  No text overlays. No confidence bars.
//  Detection can run wherever you currently run it.
//  Overlay is driven only by (debugROI, debugFullSize).
//

import UIKit
import CoreMedia
import CoreVideo
import MetalKit

@MainActor
final class DotTestViewController: UIViewController {

    private let camera = CameraCapture()
    private var lastUIUpdateTime: CFTimeInterval = 0

    private let previewView = DotTestPreviewView(
        frame: .zero,
        device: MetalRenderer.shared.device
    )

    private let roiOverlay = ROIRectOverlayLayer()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        view.layoutIfNeeded()
        previewView.drawableSize = previewView.bounds.size

        // Add ROI overlay on top of preview
        roiOverlay.frame = previewView.bounds
        previewView.layer.addSublayer(roiOverlay)

        DotTestMode.shared.previewEnabled = true
        DotTestMode.shared.isArmedForDetection = true

        camera.delegate = self
        camera.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        roiOverlay.frame = previewView.bounds
    }
}

// -----------------------------------------------------------------------------
// MARK: - CameraFrameDelegate
// -----------------------------------------------------------------------------

extension DotTestViewController: CameraFrameDelegate {

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {

        // Detection (keep whatever threading you currently use)
        DetectionQueue.shared.async {
            DotTestCoordinator.shared.processFrame(
                pixelBuffer,
                timestamp: timestamp
            )
        }

        // UI render (throttled)
        let now = CACurrentMediaTime()
        guard now - lastUIUpdateTime >= (1.0 / 60.0) else { return }
        lastUIUpdateTime = now

        let yTex = MetalRenderer.shared.makeYPlaneTexture(from: pixelBuffer)
        previewView.render(texture: yTex, isR8: true, forceSolidColor: false)

        // ROI overlay (geometry only)
        let c = DotTestCoordinator.shared
        roiOverlay.update(
            roi: c.debugROI,
            fullSize: c.debugFullSize,
            in: previewView.bounds
        )
    }
}
