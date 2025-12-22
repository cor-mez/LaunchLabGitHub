import UIKit
import CoreMedia
import MetalKit

@MainActor
final class FounderExperienceViewController: UIViewController {
    private enum ShotLifecycleState: String {
        case idle = "Idle"
        case armed = "Armed"
        case shotCaptured = "Shot Captured"
        case summary = "Summary"
    }

    private let camera = CameraCapture()
    private let previewView = FounderPreviewView(frame: .zero, device: nil)
    private let sessionManager = FounderSessionManager()
    private let displayFormatter = ShotDisplayFormatter()
    private let summaryView = ShotSummaryView()
    private let historyView = SessionHistoryView()

    private var lifecycleState: ShotLifecycleState = .idle {
        didSet { updateLifecycleBadge() }
    }
    private var pendingShot: ShotRecord?

    private let instructionLabel: UILabel = {
        let l = UILabel()
        l.text = "Founder Test Geometry: place ball in ROI and hit"
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    private let lifecycleBadge: UILabel = {
        let l = UILabel()
        l.textColor = .black
        l.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        l.textAlignment = .center
        l.backgroundColor = .systemYellow
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.text = "Idle"
        l.translatesAutoresizingMaskIntoConstraints = false
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
        view.addSubview(lifecycleBadge)
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            lifecycleBadge.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            lifecycleBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lifecycleBadge.heightAnchor.constraint(equalToConstant: 28),
            lifecycleBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            mainStack.topAnchor.constraint(equalTo: lifecycleBadge.bottomAnchor, constant: 8),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])

        summaryView.heightAnchor.constraint(equalTo: historyView.heightAnchor, multiplier: 0.8).isActive = true
    }

    private func handleShotUpdate(_ shot: ShotRecord?) {
        summaryView.update(with: shot, formatter: displayFormatter)
        historyView.update(with: sessionManager.history, formatter: displayFormatter)
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

        updateLifecycle(from: telemetry)

        if let shot = sessionManager.handleFrame(telemetry) {
            pendingShot = shot
            lifecycleState = .shotCaptured
            handleShotUpdate(shot)
            lifecycleState = .summary
        }
    }
}

// MARK: - Shot lifecycle state handling

private extension FounderExperienceViewController {
    func updateLifecycle(from telemetry: FounderFrameTelemetry) {
        if telemetry.ballLocked {
            if lifecycleState == .idle {
                lifecycleState = .armed
            }
        } else if pendingShot == nil {
            lifecycleState = .idle
        }
    }

    func updateLifecycleBadge() {
        lifecycleBadge.text = lifecycleState.rawValue

        switch lifecycleState {
        case .idle:
            lifecycleBadge.backgroundColor = .systemGray4
            lifecycleBadge.textColor = .black
        case .armed:
            lifecycleBadge.backgroundColor = .systemYellow
            lifecycleBadge.textColor = .black
        case .shotCaptured:
            lifecycleBadge.backgroundColor = .systemGreen
            lifecycleBadge.textColor = .black
        case .summary:
            lifecycleBadge.backgroundColor = .systemBlue
            lifecycleBadge.textColor = .white
            pendingShot = nil
        }
    }
}
