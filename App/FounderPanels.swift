import UIKit

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

    func update(with shot: ShotRecord?) {
        guard let shot = shot, let measured = shot.measured else {
            speedLabel.text = "—"
            angleLabel.text = "—"
            directionLabel.text = "—"
            ssiLabel.text = "—"
            impactLabel.text = "—"
            carryLabel.text = "—"
            apexLabel.text = "—"
            dispersionLabel.text = "—"
            return
        }

        speedLabel.text = measured.ballSpeedPxPerSec.map { String(format: "%.1f px/s", $0) } ?? "—"
        angleLabel.text = measured.launchAngleDeg.map { String(format: "%.1f°", $0) } ?? "—"
        directionLabel.text = measured.launchDirectionDeg.map { String(format: "%.1f°", $0) } ?? "—"
        ssiLabel.text = "\(measured.stabilityIndex)"
        impactLabel.text = measured.impact.rawValue

        carryLabel.text = shot.estimated?.carryDistance.map { String(format: "%.1f", $0) } ?? "not estimated"
        apexLabel.text = shot.estimated?.apexHeight.map { String(format: "%.1f", $0) } ?? "not estimated"
        dispersionLabel.text = shot.estimated?.dispersion.map { String(format: "%.1f", $0) } ?? "not estimated"
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

    func update(with history: [ShotRecord]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for shot in history.reversed() { // newest first
            let row = ShotHistoryRow(shot: shot)
            stack.addArrangedSubview(row)
        }
    }
}

final class ShotHistoryRow: UIView {
    init(shot: ShotRecord) {
        super.init(frame: .zero)
        let title = UILabel()
        title.textColor = .white
        title.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        title.text = "#\(shot.id)"

        let speedLabel = UILabel()
        speedLabel.textColor = .white
        speedLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        if let speed = shot.measured?.ballSpeedPxPerSec {
            speedLabel.text = String(format: "%.1f px/s", speed)
        } else {
            speedLabel.text = "—"
        }

        let angleLabel = UILabel()
        angleLabel.textColor = .white
        angleLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        angleLabel.text = shot.measured?.launchAngleDeg.map { String(format: "%.1f°", $0) } ?? "—"

        let dirLabel = UILabel()
        dirLabel.textColor = .white
        dirLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        dirLabel.text = shot.measured?.launchDirectionDeg.map { String(format: "%.1f°", $0) } ?? "—"

        let ssiLabel = UILabel()
        ssiLabel.textColor = .white
        ssiLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ssiLabel.text = shot.measured?.stabilityIndex.description ?? "—"

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
