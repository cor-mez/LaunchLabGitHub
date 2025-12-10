import UIKit

final class DetectorTelemetryView: UIView {

    private let label = UILabel()
    private let coordinator = DotTestCoordinator.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.numberOfLines = 0
        label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        label.textColor = .white
        addSubview(label)
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func refresh() {
        let teleY = coordinator.telemetryY()
        let teleCb = coordinator.telemetryCb()
        let cmp = coordinator.comparisonCPUvsGPUY()

        let yCount = teleY?.count ?? 0
        let yMin = teleY?.minValue ?? 0
        let yMax = teleY?.maxValue ?? 0
        let yMean = teleY?.meanScore ?? 0

        let cbCount = teleCb?.count ?? 0
        let cbMin = teleCb?.minValue ?? 0
        let cbMax = teleCb?.maxValue ?? 0
        let cbMean = teleCb?.meanScore ?? 0

        let matches = cmp.matches.count
        let cpuOnly = cmp.cpuOnly.count
        let gpuOnly = cmp.gpuOnly.count

        label.text =
        "GPU-Y:\n" +
        " Count: \(yCount)\n" +
        " Score: min \(yMin) max \(yMax) mean \(yMean)\n\n" +
        "GPU-Cb:\n" +
        " Count: \(cbCount)\n" +
        " Score: min \(cbMin) max \(cbMax) mean \(cbMean)\n\n" +
        "CPU vs GPU-Y:\n" +
        " Matches: \(matches)\n" +
        " CPU-only: \(cpuOnly)\n" +
        " GPU-only: \(gpuOnly)"
    }
}