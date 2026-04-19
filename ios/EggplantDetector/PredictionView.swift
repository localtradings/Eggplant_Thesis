import UIKit

enum DiagnosisDebugSource {
    case selectedTarget
    case bundledSample
}

struct DiagnosisDebugSnapshot {
    let sourceType: DiagnosisDebugSource
    let sourceLabel: String
    let previewImage: UIImage?
    let details: String
}

struct BundledDebugPresentation {
    let eyebrow: String
    let title: String
    let subtitle: String
    let details: String?
}

final class PredictionView: UIView {
    private let cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let handleView = UIView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()
    private let divider = UIView()
    private let debugDivider = UIView()
    private let debugSourceLabel = UILabel()
    private let debugPreviewImageView = UIImageView()
    private let debugDetailsLabel = UILabel()
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func render(state: DiagnosisState, mode: CaptureMode) {
        clearDebugContent()
        applyPresentationDensity(.regular)
        subtitleLabel.numberOfLines = 2
        detailsLabel.numberOfLines = 2
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

    func render(liveCardState: LiveCardState, isDebugMode: Bool) {
        _ = isDebugMode
        clearDebugContent()
        switch liveCardState {
        case .guidanceNoTarget:
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "TARGET",
                title: "Tap one plant to begin",
                subtitle: "Tap the preview to select one plant area.",
                details: nil,
                multilineDetails: false
            )

        case .analyzing:
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE",
                title: "Analyzing selected target",
                subtitle: "Hold steady while live diagnosis stabilizes.",
                details: nil,
                multilineDetails: false
            )

        case .stabilityHint:
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE",
                title: "Diagnosis not stable yet",
                subtitle: "Hold steady for a clearer leaf view.",
                details: nil,
                multilineDetails: false
            )

        case let .guidance(_, reason):
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE",
                title: reason.title,
                subtitle: reason.message,
                details: nil,
                multilineDetails: false
            )

        case let .guardBlocked(_, reason):
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE BLOCKED",
                title: "Leaf view not clear enough",
                subtitle: blockedSubtitle(for: reason),
                details: nil,
                multilineDetails: false
            )

        case let .confirmed(_, label, confidence):
            applyPresentationDensity(.regular)
            applyCardContent(
                eyebrow: "LIVE",
                title: label.replacingOccurrences(of: "_", with: " "),
                subtitle: String(format: "Stable diagnosis at %.0f%% confidence", confidence * 100),
                details: nil,
                multilineDetails: false
            )

        case let .uncertain(_, reason):
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE UNCERTAIN",
                title: reason.title,
                subtitle: "Hold steady and keep one clear leaf centered.",
                details: nil,
                multilineDetails: false
            )

        case .unavailable:
            applyPresentationDensity(.compact)
            applyCardContent(
                eyebrow: "LIVE",
                title: "Diagnosis unavailable",
                subtitle: "Try again with a steadier view.",
                details: nil,
                multilineDetails: false
            )
        }
    }

    func render(targetState: SelectedTargetState, mode: CaptureMode) {
        clearDebugContent()
        applyPresentationDensity(.compact)
        subtitleLabel.numberOfLines = 2
        detailsLabel.numberOfLines = 1
        eyebrowLabel.text = "TARGET"

        switch targetState {
        case .none:
            titleLabel.text = "Tap one plant to begin"
            subtitleLabel.text = "Select the plant area you want to analyze."
            detailsLabel.text = ""
            detailsLabel.isHidden = true
            divider.isHidden = true
        case .selected:
            titleLabel.text = "Target selected"
            subtitleLabel.text = mode == .live
                ? "Live analysis stays inside the selected target."
                : "Capture to analyze only the selected target."
            detailsLabel.text = ""
            detailsLabel.isHidden = true
            divider.isHidden = true
        case .lost:
            titleLabel.text = "Target lost. Tap again."
            subtitleLabel.text = "The previous target was cleared."
            detailsLabel.text = ""
            detailsLabel.isHidden = true
            divider.isHidden = true
        }
    }

    func render(bundledDebugPresentation: BundledDebugPresentation) {
        clearDebugContent()
        applyPresentationDensity(.regular)
        subtitleLabel.numberOfLines = 1
        detailsLabel.numberOfLines = 0
        eyebrowLabel.text = bundledDebugPresentation.eyebrow
        titleLabel.text = bundledDebugPresentation.title
        subtitleLabel.text = bundledDebugPresentation.subtitle
        detailsLabel.text = bundledDebugPresentation.details ?? ""
        detailsLabel.isHidden = bundledDebugPresentation.details == nil
        divider.isHidden = bundledDebugPresentation.details == nil
    }

    func render(debugSnapshot: DiagnosisDebugSnapshot?) {
        let shouldShow = debugSnapshot != nil
        debugDivider.isHidden = !shouldShow
        debugSourceLabel.isHidden = !shouldShow
        debugPreviewImageView.isHidden = !shouldShow || debugSnapshot?.previewImage == nil
        debugDetailsLabel.isHidden = !shouldShow

        guard let debugSnapshot else {
            debugPreviewImageView.image = nil
            debugSourceLabel.text = nil
            debugDetailsLabel.text = nil
            return
        }

        debugSourceLabel.text = debugSnapshot.sourceLabel
        debugPreviewImageView.image = debugSnapshot.previewImage
        debugDetailsLabel.text = debugSnapshot.details
    }

    private func clearDebugContent() {
        render(debugSnapshot: nil)
    }

    private enum PresentationDensity {
        case compact
        case regular
    }

    private func applyPresentationDensity(_ density: PresentationDensity) {
        switch density {
        case .compact:
            handleView.isHidden = true
            titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            titleLabel.numberOfLines = 2
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
            eyebrowLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
            detailsLabel.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
            stackTopConstraint?.constant = 10
            stackBottomConstraint?.constant = -10
        case .regular:
            handleView.isHidden = false
            titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            titleLabel.numberOfLines = 2
            subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
            eyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            detailsLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            stackTopConstraint?.constant = 12
            stackBottomConstraint?.constant = -12
        }
    }

    private func applyCardContent(
        eyebrow: String,
        title: String,
        subtitle: String,
        details: String?,
        multilineDetails: Bool
    ) {
        eyebrowLabel.text = eyebrow
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 2
        detailsLabel.text = details ?? ""
        detailsLabel.numberOfLines = multilineDetails ? 0 : 1
        detailsLabel.isHidden = details == nil
        divider.isHidden = details == nil
    }

    private func blockedSubtitle(for reason: DiagnosisReason) -> String {
        switch reason {
        case .noLeafDetected:
            return "Center one clear leaf inside the selected target."
        case .increaseLight, .reduceGlare:
            return "Adjust lighting, then hold the phone steady."
        default:
            return "Hold steady and keep a single leaf centered."
        }
    }

    private func configure() {
        backgroundColor = .clear
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = true
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        cardView.layer.borderWidth = 1
        cardView.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.10)

        handleView.translatesAutoresizingMaskIntoConstraints = false
        handleView.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        handleView.layer.cornerRadius = 2

        eyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = UIColor(red: 0.73, green: 0.95, blue: 0.64, alpha: 0.95)

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        subtitleLabel.numberOfLines = 2

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.08)

        detailsLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        detailsLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        detailsLabel.numberOfLines = 1

        debugDivider.translatesAutoresizingMaskIntoConstraints = false
        debugDivider.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        debugDivider.isHidden = true

        debugSourceLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        debugSourceLabel.textColor = UIColor(red: 0.73, green: 0.95, blue: 0.64, alpha: 0.95)
        debugSourceLabel.numberOfLines = 1
        debugSourceLabel.isHidden = true

        debugPreviewImageView.contentMode = .scaleAspectFit
        debugPreviewImageView.clipsToBounds = true
        debugPreviewImageView.layer.cornerRadius = 10
        debugPreviewImageView.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        debugPreviewImageView.isHidden = true
        debugPreviewImageView.translatesAutoresizingMaskIntoConstraints = false

        debugDetailsLabel.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        debugDetailsLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        debugDetailsLabel.numberOfLines = 0
        debugDetailsLabel.isHidden = true

        let stack = UIStackView(
            arrangedSubviews: [
                handleView,
                eyebrowLabel,
                titleLabel,
                subtitleLabel,
                divider,
                detailsLabel,
                debugDivider,
                debugSourceLabel,
                debugPreviewImageView,
                debugDetailsLabel
            ]
        )
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(6, after: handleView)
        stack.setCustomSpacing(5, after: subtitleLabel)
        stack.setCustomSpacing(5, after: detailsLabel)

        addSubview(cardView)
        cardView.contentView.addSubview(stack)

        stackTopConstraint = stack.topAnchor.constraint(equalTo: cardView.contentView.topAnchor, constant: 12)
        stackBottomConstraint = stack.bottomAnchor.constraint(equalTo: cardView.contentView.bottomAnchor, constant: -16)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -14),
            stackTopConstraint!,
            stackBottomConstraint!,

            divider.heightAnchor.constraint(equalToConstant: 1)
        ])

        handleView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        handleView.heightAnchor.constraint(equalToConstant: 4).isActive = true
        debugPreviewImageView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            render(targetState: .none, mode: .photo)
        } else {
            render(state: .needsRetake(reason: .capturePhoto), mode: .photo)
        }
        render(debugSnapshot: nil)
    }
}
