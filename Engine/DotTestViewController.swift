//
//  DotTestViewController.swift
//

import UIKit
import CoreVideo
import MetalKit

@MainActor
final class DotTestViewController: UIViewController {

    private let camera = CameraCapture()
    private let previewView = DotTestPreviewView(frame: .zero, device: nil)

    // DotTestViewController.swift

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

        DebugProbe.enabledPhases = [.capture]

        // ✅ ADD THIS LINE
        DotTestMode.shared.isArmedForDetection = true

        camera.delegate = self
        camera.start()
    }
}

// -----------------------------------------------------------------------------
// MARK: - CameraFrameDelegate
// -----------------------------------------------------------------------------

extension DotTestViewController: CameraFrameDelegate {

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer) {

        DebugProbe.probePixelBuffer(pixelBuffer)
        DebugProbe.probeYPlaneBytes(pixelBuffer, count: 16)

        let yTex = MetalRenderer.shared.makeYPlaneTexture(from: pixelBuffer)

        DotTestCoordinator.shared.processFrame(pixelBuffer)

        previewView.updateOverlay(
            fullSize: DotTestCoordinator.shared.currentFullSize(),
            roi: DotTestCoordinator.shared.currentROI(),
            sr: CGFloat(DotTestMode.shared.srScale)
        )

        previewView.render(
            texture: yTex,
            isR8: true,
            forceSolidColor: false
        )
    }
}
