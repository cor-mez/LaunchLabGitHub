//
//  FounderExperienceViewController.swift
//  LaunchLab
//
//  Founder Experience UI (V1)
//
//  ROLE (STRICT):
//  - Visualize live capture and observational telemetry
//  - Display shot outcomes ONLY if emitted by Engine authority
//  - NEVER infer, finalize, or simulate shot results
//

import UIKit
import MetalKit
import CoreMedia

@MainActor
final class FounderExperienceViewController: UIViewController,
                                             CameraFrameDelegate,
                                             FounderTelemetryObserver {

    // -----------------------------------------------------------
    // MARK: - Core Systems (OBSERVATION ONLY)
    // -----------------------------------------------------------

    private let camera = CameraCapture()
    private let previewView = FounderPreviewView(frame: .zero, device: nil)
    private let lifecycleHUD = ShotLifecycleHUDView()

    // -----------------------------------------------------------
    // MARK: - UI (NON-AUTHORITATIVE)
    // -----------------------------------------------------------

    private let summaryView = ShotSummaryView()
    private let historyView = SessionHistoryView()

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
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        historyView.translatesAutoresizingMaskIntoConstraints = false
        lifecycleHUD.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(previewView)
        view.addSubview(instructionLabel)
        view.addSubview(summaryView)
        view.addSubview(historyView)
        view.addSubview(lifecycleHUD)

        NSLayoutConstraint.activate([
            // ---------------- Preview ----------------
            previewView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            // ---------------- HUD ----------------
            lifecycleHUD.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            lifecycleHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            lifecycleHUD.widthAnchor.constraint(equalToConstant: 220),
            lifecycleHUD.heightAnchor.constraint(equalToConstant: 70),

            // ---------------- Instruction ----------------
            instructionLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            // ---------------- Summary ----------------
            summaryView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            summaryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            summaryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            summaryView.heightAnchor.constraint(equalToConstant: 120),

            // ---------------- History ----------------
            historyView.topAnchor.constraint(equalTo: summaryView.bottomAnchor),
            historyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            historyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            historyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // -------------------------------------------------------
        // MARK: - Mode Flags (NON-AUTHORITATIVE)
        // -------------------------------------------------------

        DotTestMode.shared.previewEnabled = true
        DotTestMode.shared.isArmedForDetection = false
        DotTestMode.shared.founderTestModeEnabled = true

        // -------------------------------------------------------
        // MARK: - Camera (OBSERVABILITY)
        // -------------------------------------------------------

        camera.delegate = self
        camera.start()
        camera.lockCameraForMeasurement(targetFPS: 120)
    }

    // =====================================================================
    // MARK: - CameraFrameDelegate
    // =====================================================================

    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        DotTestCoordinator.shared.processFrame(pixelBuffer, timestamp: timestamp)
    }

    // =====================================================================
    // MARK: - FounderTelemetryObserver
    // =====================================================================

    /// Per-frame telemetry — observational only
    func didUpdateFounderTelemetry(_ telemetry: FounderFrameTelemetry) {
        // Intentionally empty.
        // FounderPreviewView already reflects observational overlays.
    }

    /// Shot completion — ONLY if emitted by Engine authority
    func didCompleteShot(
        _ summary: ShotSummary,
        history: [ShotRecord],
        summaries: [ShotSummary]
    ) {
        // Defensive: Founder UI does not fabricate or infer shots.
        summaryView.update(with: summary)
        historyView.update(with: history, summaries: summaries)
    }
}
