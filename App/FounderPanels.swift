import UIKit

private struct ShotValueFormatter {
    static func mphText(from measured: ShotMeasuredData?) -> (primary: String, detail: String, color: UIColor) {
        guard let measured else { return ("—", "waiting for shot", .white) }
        switch FounderUnits.mph(fromPxPerSec: measured.ballSpeedPxPerSec) {
        case .success(let mph):
            let primary = String(format: "%.1f mph", mph)
            let detail = measured.ballSpeedPxPerSec.map { String(format: "raw %.0f px/s", $0) } ?? "raw unavailable"
            return (primary, detail, .white)
        case .failure(let error):
            let fallback = measured.ballSpeedPxPerSec.map { String(format: "raw %.0f px/s", $0) } ?? "no motion sample"
            return ("Refused", "\(error.rawValue). \(fallback)", .systemOrange)
        }
    }

    static func yardsText(from measured: ShotMeasuredData?, label: String) -> (primary: String, detail: String, color: UIColor) {
        guard let measured else { return ("—", "waiting for shot", .white) }
        switch FounderUnits.yards(fromPixels: measured.pixelDisplacement) {
        case .success(let yards):
            let primary = String(format: "%.1f yd", yards)
            let detail = measured.frameIntervalSec.map { String(format: "from %.0f px over %.0f ms", measured.pixelDisplacement ?? 0, $0 * 1000) } ?? "from raw displacement"
            return (primary, detail + " — estimated", .white)
        case .failure(let error):
            let fallback = measured.pixelDisplacement.map { String(format: "raw %.0f px", $0) } ?? "no displacement sample"
            return ("Refused", "\(label): \(error.rawValue). \(fallback)", .systemOrange)
        }
    }

    static func refusalCopy(for shot: ShotRecord?) -> String {
        guard let shot else { return "No shot yet" }
        guard shot.status == .refused else { return "Spin not reported — insufficient observability." }
        let bullets = shot.refusalReasons.map { "• \($0)" }.joined(separator: "\n")
        return bullets.isEmpty ? "Refused — observability too low" : bullets
    }
}

final class ShotLifecycleView: UIView {
    private let stateLabel = UILabel()
    private let guidanceLabel = UILabel()
    private let confidenceBar = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.05, alpha: 0.9)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        stateLabel.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        stateLabel.textColor = .white

        guidanceLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        guidanceLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        guidanceLabel.numberOfLines = 0

        confidenceBar.trackTintColor = UIColor.white.withAlphaComponent(0.1)
        confidenceBar.tintColor = .systemGreen

        let stack = UIStackView(arrangedSubviews: [stateLabel, guidanceLabel, confidenceBar])
        stack.axis = .vertical
        stack.spacing = 6

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        update(state: .idle)
    }

    func update(state: ShotLifecycleState) {
        switch state {
        case .idle:
            stateLabel.text = "IDLE"
            guidanceLabel.text = "Place ball in ROI to arm shot capture."
            confidenceBar.progress = 0
            confidenceBar.tintColor = .systemGray
        case .armed(let confidence):
            stateLabel.text = "ARMED"
            guidanceLabel.text = "Hold still until lock is solid, then swing."
            confidenceBar.progress = min(max(confidence / 20.0, 0), 1)
            confidenceBar.tintColor = confidenceBar.progress > 0.6 ? .systemGreen : .systemYellow
        case .captured(let shot):
            stateLabel.text = "SHOT CAPTURED"
            guidanceLabel.text = "Processing shot #\(shot.id)…"
            confidenceBar.progress = 1
            confidenceBar.tintColor = .systemGreen
        case .summary(let shot):
            stateLabel.text = "SUMMARY"
            guidanceLabel.text = shot.status == .refused ? "Refused — adjust lighting/framing and retry." : "Shot #\(shot.id) ready."
            confidenceBar.progress = 1
            confidenceBar.tintColor = shot.status == .refused ? .systemOrange : .systemGreen
        }
    }
}

final class FlightVisualizerView: UIView {
    private let caption: UILabel = {
        let l = UILabel()
        l.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textColor = .white
        l.text = "ESTIMATED FLIGHT (STRAIGHT LINE)"
        return l
    }()

    private var shot: ShotRecord?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.05, alpha: 0.6)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.05).cgColor

        addSubview(caption)
        caption.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func update(with shot: ShotRecord?) {
        self.shot = shot
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let measured = shot?.measured,
              let angle = measured.launchAngleDeg,
              let direction = measured.launchDirectionDeg else {
            drawPlaceholder(in: rect)
            return
        }

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        let origin = CGPoint(x: rect.minX + 20, y: rect.maxY - 20)
        let scale: CGFloat = min(rect.width, rect.height) * 0.5

        let rad = CGFloat(angle * .pi / 180)
        let dirRad = CGFloat(direction * .pi / 180)
        let rangeVector = CGPoint(x: cos(dirRad) * cos(rad), y: -sin(rad))

        let apex = CGPoint(x: origin.x + rangeVector.x * scale * 0.5,
                           y: origin.y + rangeVector.y * scale * 0.6)
        let end = CGPoint(x: origin.x + rangeVector.x * scale,
                          y: origin.y + rangeVector.y * scale)

        ctx.setStrokeColor(UIColor.systemTeal.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: origin)
        ctx.addQuadCurve(to: end, control: apex)
        ctx.strokePath()

        ctx.setFillColor(UIColor.systemGray.cgColor)
        ctx.fillEllipse(in: CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8))

        let estText = "estimated"
        estText.draw(at: CGPoint(x: origin.x, y: origin.y - 14), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.white
        ])
    }

    private func drawPlaceholder(in rect: CGRect) {
        let text = "Awaiting shot for visualization"
        text.draw(in: rect.insetBy(dx: 8, dy: 8), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6)
        ])
    }
}

final class ShotSummaryView: UIView {
    private let measuredTitle = ShotSummaryView.makeTitle("MEASURED")
    private let estimatedTitle = ShotSummaryView.makeTitle("ESTIMATED")
    private let refusedTitle = ShotSummaryView.makeTitle("REFUSED")

    private let speedLabel = ShotSummaryView.makeValueLabel()
    private let speedDetailLabel = ShotSummaryView.makeDetailLabel()
    private let angleLabel = ShotSummaryView.makeValueLabel()
    private let directionLabel = ShotSummaryView.makeValueLabel()
    private let ssiLabel = ShotSummaryView.makeValueLabel()
    private let impactLabel = ShotSummaryView.makeValueLabel()

    private let carryLabel = ShotSummaryView.makeValueLabel()
    private let carryDetailLabel = ShotSummaryView.makeDetailLabel()
    private let apexLabel = ShotSummaryView.makeValueLabel()
    private let apexDetailLabel = ShotSummaryView.makeDetailLabel()
    private let dispersionLabel = ShotSummaryView.makeValueLabel()

    private let refusalLabel: UILabel = {
        let l = ShotSummaryView.makeDetailLabel()
        l.textColor = .systemOrange
        l.numberOfLines = 3
        l.textAlignment = .left
        return l
    }()

    private let flightView = FlightVisualizerView()

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
            makeRow(title: "Ball Speed", value: speedLabel, detail: speedDetailLabel),
            makeRow(title: "Launch Angle", value: angleLabel),
            makeRow(title: "Direction", value: directionLabel),
            makeRow(title: "Shot Stability Index", value: ssiLabel),
            makeRow(title: "Impact", value: impactLabel)
        ])
        measuredStack.axis = .vertical
        measuredStack.spacing = 8

        let estimatedStack = UIStackView(arrangedSubviews: [
            makeRow(title: "Carry Distance", value: carryLabel, detail: carryDetailLabel),
            makeRow(title: "Apex Height", value: apexLabel, detail: apexDetailLabel),
            makeRow(title: "Dispersion Cone", value: dispersionLabel)
        ])
        estimatedStack.axis = .vertical
        estimatedStack.spacing = 8

        refusalLabel.text = "Spin not reported — insufficient observability."
        let refusedStack = UIStackView(arrangedSubviews: [refusalLabel])
        refusedStack.axis = .vertical

        flightView.translatesAutoresizingMaskIntoConstraints = false
        flightView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            measuredTitle, measuredStack,
            estimatedTitle, estimatedStack,
            flightView,
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
        l.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        l.textAlignment = .right
        return l
    }

    private static func makeDetailLabel() -> UILabel {
        let l = UILabel()
        l.textColor = UIColor.white.withAlphaComponent(0.85)
        l.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        l.textAlignment = .right
        return l
    }

    private func makeRow(title: String, value: UILabel, detail: UILabel? = nil) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor(white: 0.9, alpha: 1)
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let column = UIStackView(arrangedSubviews: detail != nil ? [value, detail!] : [value])
        column.axis = .vertical
        column.spacing = 2

        let row = UIStackView(arrangedSubviews: [titleLabel, column])
        row.axis = .horizontal
        row.distribution = .equalSpacing
        return row
    }

    func update(with shot: ShotRecord?) {
        guard let shot = shot else {
            resetLabels()
            return
        }

        let mph = ShotValueFormatter.mphText(from: shot.measured)
        speedLabel.text = mph.primary
        speedLabel.textColor = mph.color
        speedDetailLabel.text = mph.detail

        if let angle = shot.measured?.launchAngleDeg {
            angleLabel.text = String(format: "%.1f°", angle)
        } else {
            angleLabel.text = "—"
        }

        if let direction = shot.measured?.launchDirectionDeg {
            directionLabel.text = String(format: "%.1f°", direction)
        } else {
            directionLabel.text = "—"
        }

        if let stability = shot.measured?.stabilityIndex {
            ssiLabel.text = "\(stability)"
        } else {
            ssiLabel.text = "—"
        }

        impactLabel.text = shot.measured?.impact.rawValue ?? "—"

        let carry = ShotValueFormatter.yardsText(from: shot.measured, label: "carry")
        carryLabel.text = carry.primary
        carryLabel.textColor = carry.color
        carryDetailLabel.text = carry.detail

        let apex = ShotValueFormatter.yardsText(from: shot.measured, label: "apex")
        apexLabel.text = apex.primary
        apexLabel.textColor = apex.color
        apexDetailLabel.text = apex.detail

        dispersionLabel.text = shot.estimated?.dispersion.map { String(format: "%.1f", $0) } ?? "line-only"

        refusalLabel.text = ShotValueFormatter.refusalCopy(for: shot)
        flightView.update(with: shot)
    }

    private func resetLabels() {
        [speedLabel, angleLabel, directionLabel, ssiLabel, impactLabel, carryLabel, apexLabel, dispersionLabel].forEach { $0.text = "—" }
        speedDetailLabel.text = "waiting for shot"
        carryDetailLabel.text = "waiting for shot"
        apexDetailLabel.text = "waiting for shot"
        refusalLabel.text = "Spin not reported — insufficient observability."
        flightView.update(with: nil)
    }
}

final class SessionHistoryView: UIView {
    private let stack = UIStackView()
    private let scrollView = UIScrollView()

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

        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        let container = UIStackView(arrangedSubviews: [title, scrollView])
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

        let timestamp = UILabel()
        timestamp.textColor = UIColor.white.withAlphaComponent(0.8)
        timestamp.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        timestamp.text = formatter.string(from: shot.timestamp)

        let speedLabel = UILabel()
        speedLabel.textColor = .white
        speedLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let mph = ShotValueFormatter.mphText(from: shot.measured)
        speedLabel.text = mph.primary

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
            backgroundColor = UIColor.systemOrange.withAlphaComponent(0.3)
        } else if stability >= 70 {
            backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        } else if stability >= 40 {
            backgroundColor = UIColor.systemYellow.withAlphaComponent(0.3)
        } else {
            backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        }

        let row = UIStackView(arrangedSubviews: [title, timestamp, speedLabel, angleLabel, dirLabel, ssiLabel, statusLabel])
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
