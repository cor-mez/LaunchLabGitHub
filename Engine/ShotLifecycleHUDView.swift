//
//  ShotLifecycleHUDView.swift
//  LaunchLab
//
//  Debug-only HUD for visualizing shot lifecycle state.
//

import UIKit

@MainActor
final class ShotLifecycleHUDView: UIView {

    private let label = UILabel()
    private let lifecycleHUD = ShotLifecycleHUDView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 8
        clipsToBounds = true

        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .green
        label.numberOfLines = 0
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    func update(
        state: ShotLifecycleState,
        confidence: Float,
        motionPhase: MotionDensityPhase
    ) {
        label.text =
        """
        STATE: \(state.rawValue)
        CONF:  \(String(format: "%.2f", confidence))
        MOTION: \(motionPhase.rawValue)
        """
    }
}
