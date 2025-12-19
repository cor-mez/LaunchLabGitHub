import UIKit
import CoreMedia
import MetalKit

@MainActor
final class FounderExperienceViewController: UIViewController {
    private let camera = CameraCapture()
    private let previewView = FounderPreviewView(frame: .zero, device: nil)
    private let sessionManager = FounderSessionManager()
    private let summaryView = ShotSummaryView()
    private let historyView = SessionHistoryView()

    private let instructionLabel: UILabel = {
        let l = UILabel()
        l.text = "Founder Test Geometry: place ball in ROI and hit"
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()

        view.backgroundColor = .black
        DotTestMode.shared.isArmedForDetection = true
        DotTestMode.shared.founderTestModeEnabled = true
        DotTestCoordinator.shared.founderDelegate = self

        camera.delegate = self
        camera.start()
    }

    private func setupLayout() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        historyView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        let panelStack = UIStackView(arrangedSubviews: [summaryView, historyView])
        panelStack.axis = .vertical
        panelStack.spacing = 12

        let mainStack = UIStackView(arrangedSubviews: [previewView, panelStack])
        mainStack.axis = .horizontal
        mainStack.alignment = .fill
        mainStack.distribution = .fillEqually
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(instructionLabel)
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            mainStack.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])

        summaryView.heightAnchor.constraint(equalTo: historyView.heightAnchor, multiplier: 0.8).isActive = true
    }

    private func handleShotUpdate(_ shot: ShotRecord?) {
        summaryView.update(with: shot)
        historyView.update(with: sessionManager.history)
    }
}

extension FounderExperienceViewController: CameraFrameDelegate {
    func cameraDidOutput(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let yTex = MetalRenderer.shared.makeYPlaneTexture(from: pixelBuffer)
        DotTestCoordinator.shared.processFrame(pixelBuffer, timestamp: timestamp)

        previewView.render(
            texture: yTex,
            isR8: true
        )
    }
}

extension FounderExperienceViewController: FounderTelemetryObserver {
    func didUpdateFounderTelemetry(_ telemetry: FounderFrameTelemetry) {
        previewView.updateOverlay(
            roi: telemetry.roi,
            fullSize: telemetry.fullSize,
            ballLocked: telemetry.ballLocked,
            confidence: telemetry.confidence
        )

        if let shot = sessionManager.handleFrame(telemetry) {
            handleShotUpdate(shot)
        }
    }
}
