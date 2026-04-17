import UIKit

final class PredictionView: UIView {
    private let cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()
    private let divider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func render(state: DiagnosisState, mode: CaptureMode) {
        switch state {
        case let .confirmed(label, confidence, topResults):
            eyebrowLabel.text = mode == .live ? "LIVE" : "PHOTO"
            titleLabel.text = label.replacingOccurrences(of: "_", with: " ")
            if mode == .live {
                subtitleLabel.text = String(format: "%.0f%% confidence", confidence * 100)
                detailsLabel.text = ""
                detailsLabel.isHidden = true
                divider.isHidden = true
            } else {
                subtitleLabel.text = String(format: "Confidence %.0f%%", confidence * 100)
                detailsLabel.text = topResults
                    .prefix(1)
                    .map { String(format: "%@: %.0f%%", $0.label.replacingOccurrences(of: "_", with: " "), $0.confidence * 100) }
                    .joined(separator: "  •  ")
                detailsLabel.isHidden = detailsLabel.text?.isEmpty ?? true
                divider.isHidden = detailsLabel.isHidden
            }

        case let .uncertain(topResults, reason):
            eyebrowLabel.text = "UNCERTAIN"
            titleLabel.text = reason.title
            subtitleLabel.text = "Retake with one centered leaf."
            detailsLabel.text = topResults
                .prefix(1)
                .map { String(format: "%@: %.0f%%", $0.label.replacingOccurrences(of: "_", with: " "), $0.confidence * 100) }
                .joined(separator: "  •  ")
            detailsLabel.isHidden = false
            divider.isHidden = false

        case let .needsRetake(reason):
            eyebrowLabel.text = "GUIDANCE"
            titleLabel.text = reason.title
            subtitleLabel.text = reason.message
            detailsLabel.text = ""
            detailsLabel.isHidden = true
            divider.isHidden = true
        }
    }

    func render(targetState: SelectedTargetState) {
        eyebrowLabel.text = "TARGET"
        detailsLabel.isHidden = false
        divider.isHidden = false
        detailsLabel.text = "Phase 1 keeps selection manual and offline. Future detector and tracker hooks are ready."

        switch targetState {
        case .none:
            titleLabel.text = "Tap one eggplant plant to begin"
            subtitleLabel.text = "Tap the preview to select one plant area."
        case .selected:
            titleLabel.text = "Target selected"
            subtitleLabel.text = "Tap another plant to reselect, or reset the current target."
        case .lost:
            titleLabel.text = "Target lost. Tap again."
            subtitleLabel.text = "The previous target was cleared."
        }
    }

    private func configure() {
        backgroundColor = .clear
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 16
        cardView.clipsToBounds = true
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        cardView.layer.borderWidth = 1

        eyebrowLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        eyebrowLabel.textColor = UIColor(red: 0.73, green: 0.95, blue: 0.64, alpha: 0.95)

        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        subtitleLabel.font = .systemFont(ofSize: 9, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.8

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.08)

        detailsLabel.font = .monospacedSystemFont(ofSize: 7, weight: .medium)
        detailsLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        detailsLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, subtitleLabel, divider, detailsLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: cardView.contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.contentView.bottomAnchor, constant: -9),

            divider.heightAnchor.constraint(equalToConstant: 1)
        ])

        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            render(targetState: .none)
        } else {
            render(state: .needsRetake(reason: .capturePhoto), mode: .photo)
        }
    }
}
