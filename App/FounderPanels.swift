import UIKit

struct ShotDisplayFormatter {
    var pixelsPerMeter: Double? = nil

    private func convertSpeedToMph(_ pxPerSec: Double) -> Double? {
        guard let pixelsPerMeter else { return nil }
        let metersPerSec = pxPerSec / pixelsPerMeter
        return metersPerSec * 2.23693629
    }

    private func convertDistanceToYards(_ distancePx: Double) -> Double? {
        guard let pixelsPerMeter else { return nil }
        let meters = distancePx / pixelsPerMeter
        return meters * 1.0936133
    }

    func speedText(from measured: ShotMeasuredData?) -> String {
        guard let measured else { return "Refused" }
        guard let pxSpeed = measured.ballSpeedPxPerSec else { return "Refused" }

        if let mph = convertSpeedToMph(pxSpeed) {
            return String(format: "Measured: %.1f mph (%.1f px/s)", mph, pxSpeed)
        } else {
            return String(format: "Refused (%.1f px/s, no calibration)", pxSpeed)
        }
    }

    func launchAngleText(from measured: ShotMeasuredData?) -> String {
        guard let measured else { return "Refused" }
        return measured.launchAngleDeg.map { String(format: "Measured: %.1f°", $0) } ?? "Refused"
    }

    func directionText(from measured: ShotMeasuredData?) -> String {
        guard let measured else { return "Refused" }
        return measured.launchDirectionDeg.map { String(format: "Measured: %.1f°", $0) } ?? "Refused"
    }

    func stabilityText(from measured: ShotMeasuredData?) -> String {
        guard let measured else { return "Refused" }
        return "Measured: \(measured.stabilityIndex)"
    }

    func impactText(from measured: ShotMeasuredData?) -> String {
        guard let measured else { return "Refused" }
        return "Measured: \(measured.impact.rawValue)"
    }

    func carryText(from estimated: ShotEstimatedData?) -> String {
        guard let estimated else { return "Refused" }
        guard let carryPx = estimated.carryDistance else { return "Refused" }

        if let yards = convertDistanceToYards(carryPx) {
            return String(format: "Estimated: %.1f yd (%.1f px)", yards, carryPx)
        } else {
            return String(format: "Refused (%.1f px, no calibration)", carryPx)
        }
    }

    func apexText(from estimated: ShotEstimatedData?) -> String {
        guard let estimated else { return "Refused" }
        guard let apexPx = estimated.apexHeight else { return "Refused" }

        if let yards = convertDistanceToYards(apexPx) {
            return String(format: "Estimated: %.1f yd (%.1f px)", yards, apexPx)
        } else {
            return String(format: "Refused (%.1f px, no calibration)", apexPx)
        }
    }

    func dispersionText(from estimated: ShotEstimatedData?) -> String {
        guard let estimated else { return "Refused" }
        guard let dispersionPx = estimated.dispersion else { return "Refused" }

        if let yards = convertDistanceToYards(dispersionPx) {
            return String(format: "Estimated: %.1f yd (%.1f px)", yards, dispersionPx)
        } else {
            return String(format: "Refused (%.1f px, no calibration)", dispersionPx)
        }
    }
}

final class ShotSummaryView: UIView {
    private let measuredTitle = ShotSummaryView.makeTitle("MEASURED")
    private let estimatedTitle = ShotSummaryView.makeTitle("ESTIMATED")
    private let refusedTitle = ShotSummaryView.makeTitle("REFUSED")

    private let speedLabel = ShotSummaryView.makeValueLabel()
    private let angleLabel = ShotSummaryView.makeValueLabel()
    private let directionLabel = ShotSummaryView.makeValueLabel()
    private let ssiLabel = ShotSummaryView.makeValueLabel()
    private let impactLabel = ShotSummaryView.makeValueLabel()

    private let carryLabel = ShotSummaryView.makeValueLabel()
    private let apexLabel = ShotSummaryView.makeValueLabel()
    private let dispersionLabel = ShotSummaryView.makeValueLabel()

    private let spinCopyLabel: UILabel = {
        let l = ShotSummaryView.makeValueLabel()
        l.textColor = .systemRed
        l.textAlignment = .left
        l.numberOfLines = 2
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        layer.cornerRadius = 12
        layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        layer.borderWidth = 1

        let measuredStack = UIStackView(arrangedSubviews: [
            makeRow(title: "Ball Speed", value: speedLabel),
            makeRow(title: "Launch Angle", value: angleLabel),
            makeRow(title: "Direction", value: directionLabel),
            makeRow(title: "Shot Stability Index", value: ssiLabel),
            makeRow(title: "Impact", value: impactLabel)
        ])
        measuredStack.axis = .vertical
        measuredStack.spacing = 6

        let estimatedStack = UIStackView(arrangedSubviews: [
            makeRow(title: "Carry Distance", value: carryLabel),
            makeRow(title: "Apex Height", value: apexLabel),
            makeRow(title: "Dispersion Cone", value: dispersionLabel)
        ])
        estimatedStack.axis = .vertical
        estimatedStack.spacing = 6

        spinCopyLabel.text = "Spin not reported — insufficient observability."

        let refusedStack = UIStackView(arrangedSubviews: [spinCopyLabel])
        refusedStack.axis = .vertical

        let stack = UIStackView(arrangedSubviews: [
            measuredTitle, measuredStack,
            estimatedTitle, estimatedStack,
            refusedTitle, refusedStack
        ])
        stack.axis = .vertical
        stack.spacing = 10

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private static func makeTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        return l
    }

    private static func makeValueLabel() -> UILabel {
        let l = UILabel()
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        l.textAlignment = .right
        return l
    }

    private func makeRow(title: String, value: UILabel) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor(white: 0.9, alpha: 1)
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let row = UIStackView(arrangedSubviews: [titleLabel, value])
        row.axis = .horizontal
        row.distribution = .equalSpacing
        return row
    }

    func update(with shot: ShotRecord?, formatter: ShotDisplayFormatter) {
        guard let shot else {
            speedLabel.text = "Refused"
            angleLabel.text = "Refused"
            directionLabel.text = "Refused"
            ssiLabel.text = "Refused"
            impactLabel.text = "Refused"
            carryLabel.text = "Refused"
            apexLabel.text = "Refused"
            dispersionLabel.text = "Refused"
            return
        }

        speedLabel.text = formatter.speedText(from: shot.measured)
        angleLabel.text = formatter.launchAngleText(from: shot.measured)
        directionLabel.text = formatter.directionText(from: shot.measured)
        ssiLabel.text = formatter.stabilityText(from: shot.measured)
        impactLabel.text = formatter.impactText(from: shot.measured)

        carryLabel.text = formatter.carryText(from: shot.estimated)
        apexLabel.text = formatter.apexText(from: shot.estimated)
        dispersionLabel.text = formatter.dispersionText(from: shot.estimated)
    }
}

final class SessionHistoryView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.06, alpha: 0.9)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.05).cgColor

        let title = UILabel()
        title.text = "SESSION HISTORY"
        title.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white

        stack.axis = .vertical
        stack.spacing = 6

        let container = UIStackView(arrangedSubviews: [title, stack])
        container.axis = .vertical
        container.spacing = 10

        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    func update(with history: [ShotRecord], formatter: ShotDisplayFormatter) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for shot in history.reversed() { // newest first
            let row = ShotHistoryRow(shot: shot, formatter: formatter)
            stack.addArrangedSubview(row)
        }
    }
}

final class ShotHistoryRow: UIView {
    init(shot: ShotRecord, formatter: ShotDisplayFormatter) {
        super.init(frame: .zero)
        let title = UILabel()
        title.textColor = .white
        title.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        title.text = "#\(shot.id)"

        let speedLabel = UILabel()
        speedLabel.textColor = .white
        speedLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        speedLabel.text = formatter.speedText(from: shot.measured)

        let angleLabel = UILabel()
        angleLabel.textColor = .white
        angleLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        angleLabel.text = formatter.launchAngleText(from: shot.measured)

        let dirLabel = UILabel()
        dirLabel.textColor = .white
        dirLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        dirLabel.text = formatter.directionText(from: shot.measured)

        let ssiLabel = UILabel()
        ssiLabel.textColor = .white
        ssiLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ssiLabel.text = formatter.stabilityText(from: shot.measured)

        let statusLabel = UILabel()
        statusLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .black
        statusLabel.textAlignment = .center

        switch shot.status {
        case .measured:
            statusLabel.text = "Measured"
        case .estimated:
            statusLabel.text = "Estimated"
        case .refused:
            statusLabel.text = "Refused"
        }

        let stability = shot.measured?.stabilityIndex ?? 0
        if shot.status == .refused {
            backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        } else if stability >= 70 {
            backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        } else if stability >= 40 {
            backgroundColor = UIColor.systemYellow.withAlphaComponent(0.3)
        } else {
            backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        }

        let row = UIStackView(arrangedSubviews: [title, speedLabel, angleLabel, dirLabel, ssiLabel, statusLabel])
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .equalSpacing
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        layer.cornerRadius = 8
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
