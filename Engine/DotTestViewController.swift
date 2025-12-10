import UIKit
import MetalKit
import CoreVideo

final class DotTestViewController: UIViewController {

    private let preview = DotTestPreviewView(frame: .zero, device: MetalRenderer.shared.device)
    private let telemetry = DetectorTelemetryView()
    private let camera = CameraCapture()
    private let renderer = DotTestCameraRenderer.shared
    private let coordinator = DotTestCoordinator.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        preview.frame = view.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(preview)

        telemetry.frame = CGRect(x: 10, y: 50, width: 260, height: 220)
        telemetry.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        view.addSubview(telemetry)

        camera.onFrame = { [weak self] pb in
            guard let self = self else { return }
            self.renderer.processFrame(pb, in: self.preview)
            self.telemetry.refresh()
        }

        camera.start()
    }

    func setBackend(_ b: DetectorBackend) {
        coordinator.setBackend(b)
    }

    func setDebugSurface(_ s: DotTestDebugSurface) {
        preview.updateDebugSurface(s)
    }

    func setROI(_ r: CGRect) {
        coordinator.setROI(r)
        preview.updateROI(r)
    }

    func setSRScale(_ s: Float) {
        coordinator.setSRScale(s)
    }

    func toggleFreeze() {
        coordinator.toggleFreeze()
    }
}