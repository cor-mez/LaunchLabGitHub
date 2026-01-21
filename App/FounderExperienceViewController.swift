//
//  FounderExperienceViewController.swift
//  LaunchLab
//
//  Founder Experience UI (V1)
//
//  ROLE (STRICT):
//  - Visualize live capture and observational telemetry
//  - Display lifecycle state and refusals only
//  - NEVER infer, finalize, or simulate shot results
//

import UIKit
import MetalKit
import CoreMedia

@MainActor
final class FounderExperienceViewController: UIViewController,
                                             CameraFrameDelegate {

    // -----------------------------------------------------------
    // MARK: - Core Systems (OBSERVATION ONLY)
    // -----------------------------------------------------------

    private let camera = CameraCapture()
    private let previewView = FounderPreviewView(
        frame: .zero,
        device: MetalRenderer.shared.device
    )
    private let lifecycleHUD = ShotLifecycleHUDView()

    // -----------------------------------------------------------
    // MARK: - UI
    // -----------------------------------------------------------

    private let instructionLabel: UILabel = {
        let l = UILabel()
        l.text = "Founder Mode: observe capture & refusal behavior"
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    // -----------------------------------------------------------
    // MARK: - Lifecycle
    // -----------------------------------------------------------

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        previewView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        lifecycleHUD.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(previewView)
        view.addSubview(instructionLabel)
        view.addSubview(lifecycleHUD)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),

            lifecycleHUD.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            lifecycleHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            lifecycleHUD.widthAnchor.constraint(equalToConstant: 220),
            lifecycleHUD.heightAnchor.constraint(equalToConstant: 70),

            instructionLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])

        DotTestMode.shared.previewEnabled = true
        DotTestMode.shared.isArmedForDetection = false
        DotTestMode.shared.founderTestModeEnabled = true

        camera.delegate = self
        camera.start()
        camera.lockCameraForMeasurement(targetFPS: 120)
    }

    // -----------------------------------------------------------
    // MARK: - CameraFrameDelegate
    // -----------------------------------------------------------

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {

        // 🔑 Preview owns rendering
        previewView.update(pixelBuffer: pixelBuffer)

        // Engine observability
        DotTestCoordinator.shared.processFrame(
            pixelBuffer,
            timestamp: timestamp
        )
    }
}
