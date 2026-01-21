//
//  DotTestViewController.swift
//  LaunchLab
//
//  Camera preview + ROI overlay (OBSERVABILITY ONLY)
//
//  STRICT ROLE:
//  - Show live camera preview
//  - Visualize engine-selected ROI
//  - Feed frames into observability pipeline
//  - NO authority, NO lifecycle, NO decisions
//

import UIKit
import CoreMedia
import MetalKit

@MainActor
final class DotTestViewController: UIViewController, CameraFrameDelegate {

    // ---------------------------------------------------------
    // MARK: - Core
    // ---------------------------------------------------------

    private let camera = CameraCapture()

    private let previewView = FounderPreviewView(
        frame: .zero,
        device: MetalRenderer.shared.device
    )

    private let roiOverlay = ROIRectOverlayLayer()

    // ---------------------------------------------------------
    // MARK: - Lifecycle
    // ---------------------------------------------------------

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // ---------------- Preview ----------------
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // ---------------- ROI Overlay ----------------
        roiOverlay.frame = previewView.bounds
        previewView.layer.addSublayer(roiOverlay)

        // ---------------- Mode Flags ----------------
        DotTestMode.shared.previewEnabled = true
        DotTestMode.shared.isArmedForDetection = false

        // ---------------- Camera ----------------
        camera.delegate = self
        camera.start()
        camera.lockCameraForMeasurement(targetFPS: 120)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        roiOverlay.frame = previewView.bounds
    }

    // ---------------------------------------------------------
    // MARK: - CameraFrameDelegate
    // ---------------------------------------------------------

    func cameraDidOutput(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) {
        // -----------------------------------------------------
        // 1) Live preview (UI only)
        // -----------------------------------------------------
        previewView.update(pixelBuffer: pixelBuffer)

        // -----------------------------------------------------
        // 2) Engine observability
        // -----------------------------------------------------
        DotTestCoordinator.shared.processFrame(
            pixelBuffer,
            timestamp: timestamp
        )

        // -----------------------------------------------------
        // 3) ROI overlay (OBSERVABILITY ONLY)
        // -----------------------------------------------------
        let roi = DotTestCoordinator.shared.debugROI
        let fullSize = DotTestCoordinator.shared.debugFullSize

        guard
            roi.width > 0,
            roi.height > 0,
            fullSize.width > 0,
            fullSize.height > 0
        else { return }

        roiOverlay.update(
            roi: roi,
            fullSize: fullSize,
            in: previewView.bounds
        )
    }
}
