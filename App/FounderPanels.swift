import UIKit

// MARK: - ShotSummaryView (Authoritative-only display surface)
//
// IMPORTANT:
// - This view does NOT compute or infer shots.
// - It only displays whatever authoritative summary is provided (if any).
//

final class ShotSummaryView: UIView {

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "LAST AUTHORITATIVE SHOT"
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        return l
    }()

    private let bodyLabel: UILabel = {
        let l = UILabel()
        l.textColor = .white
        l.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        l.numberOfLines = 0
        l.textAlignment = .left
        l.text = "—"
        return l
    }()

    private let footerLabel: UILabel = {
        let l = UILabel()
        l.textColor = UIColor.systemRed
        l.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        l.numberOfLines = 2
        l.textAlignment = .left
        l.text = "Refusal-first: shots may never appear until authority is enabled."
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

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, footerLabel])
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

    /// Update with an authoritative engine summary (if any).
    /// This method never implies a shot occurred; it only renders what it is given.
    func update(with summary: EngineShotSummary?) {
        guard let summary else {
            bodyLabel.text = "—"
            return
        }
        bodyLabel.text = String(describing: summary)
    }
}

// MARK: - SessionHistoryView (Authoritative-only history)
//
// IMPORTANT:
// - Displays a list of authoritative EngineShotSummary entries.
// - No ShotRecord / ShotStatus / inferred results.
//
final class SessionHistoryView: UIView {

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "AUTHORITATIVE HISTORY"
        l.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        return l
    }()

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

        stack.axis = .vertical
        stack.spacing = 6

        let container = UIStackView(arrangedSubviews: [titleLabel, stack])
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

    func update(with summaries: [EngineShotSummary]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !summaries.isEmpty else {
            let empty = UILabel()
            empty.text = "—"
            empty.textColor = UIColor(white: 0.8, alpha: 1.0)
            empty.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            stack.addArrangedSubview(empty)
            return
        }

        // newest first
        for (i, s) in summaries.reversed().enumerated() {
            let row = ShotHistoryRow(indexFromNewest: i, summary: s)
            stack.addArrangedSubview(row)
        }
    }
}

// MARK: - ShotHistoryRow (Authoritative-only)
final class ShotHistoryRow: UIView {

    init(indexFromNewest: Int, summary: EngineShotSummary) {
        super.init(frame: .zero)

        backgroundColor = UIColor.white.withAlphaComponent(0.05)
        layer.cornerRadius = 8
        clipsToBounds = true

        let idxLabel = UILabel()
        idxLabel.textColor = .white
        idxLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        idxLabel.text = "#\(indexFromNewest)"

        let summaryLabel = UILabel()
        summaryLabel.textColor = .white
        summaryLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        summaryLabel.numberOfLines = 2
        summaryLabel.textAlignment = .left
        summaryLabel.text = String(describing: summary)

        let row = UIStackView(arrangedSubviews: [idxLabel, summaryLabel])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 10

        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
