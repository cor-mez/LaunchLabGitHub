//
//  DotTestViewController.swift
//  LaunchLab
//
//  Log-only detection view.
//  No overlays. No ROI visualization.
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

        DotTestMode.shared.previewEnabled = true
        DotTestMode.shared.isArmedForDetection = true

        camera.delegate = self
        camera.start()
    }
}

// -----------------------------------------------------------------------------
// MARK: - CameraFrameDelegate
// -----------------------------------------------------------------------------

extension DotTestViewController: CameraFrameDelegate {

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {

        // ---------------------------------------------------------
        // Detection (BACKGROUND ONLY — NEVER MainActor)
        // ---------------------------------------------------------
        DetectionQueue.shared.async {
            DotTestCoordinator.shared.processFrame(
                pixelBuffer,
                timestamp: timestamp
            )
        }

        // ---------------------------------------------------------
        // UI Rendering (throttled, MainActor-safe)
        // ---------------------------------------------------------
        let now = CACurrentMediaTime()
        guard now - lastUIUpdateTime >= (1.0 / 60.0) else { return }
        lastUIUpdateTime = now

        let yTex = MetalRenderer.shared.makeYPlaneTexture(from: pixelBuffer)

        previewView.render(
            texture: yTex,
            isR8: true,
            forceSolidColor: false
        )
    }
}
