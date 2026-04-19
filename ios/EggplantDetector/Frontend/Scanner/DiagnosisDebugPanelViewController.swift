import UIKit

final class DiagnosisDebugPanelViewController: UIViewController {
    var onRunBundledSample: (() -> Void)?
    var onSelectedSource: ((DiagnosisDebugSource) -> Void)?
    var onDismiss: (() -> Void)?

    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let sourceControl = UISegmentedControl(items: ["Camera", "Bundled"])
    private let runButton = UIButton(type: .system)
    private let previewCard = UIView()
    private let previewImageView = UIImageView()
    private let detailsTextView = UITextView()
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil {
            onDismiss?()
        }
    }

    func setRunning(_ isRunning: Bool) {
        runButton.isEnabled = !isRunning
        runButton.configuration?.title = isRunning ? "Running…" : "Run Bundled Sample"
    }

    func render(
        selectedSource: DiagnosisDebugSource,
        cameraSnapshot: DiagnosisDebugSnapshot?,
        bundledSnapshot: DiagnosisDebugSnapshot?,
        bundledPresentation: BundledDebugPresentation?
    ) {
        let hasCamera = cameraSnapshot != nil
        let hasBundled = bundledSnapshot != nil

        sourceControl.isHidden = !(hasCamera && hasBundled)
        if hasCamera && hasBundled {
            sourceControl.selectedSegmentIndex = selectedSource == .selectedTarget ? 0 : 1
        }

        let snapshot: DiagnosisDebugSnapshot?
        let title: String
        let subtitle: String
        let details: String
        let showEmptyState: Bool

        switch selectedSource {
        case .selectedTarget:
            snapshot = cameraSnapshot
            title = "Camera Debug"
            subtitle = "Latest selected-target crop diagnostics from the live camera path."
            details = cameraSnapshot?.details ?? "No camera debug snapshot is available yet."
            showEmptyState = cameraSnapshot == nil

        case .bundledSample:
            snapshot = bundledSnapshot
            title = bundledPresentation?.title ?? "Bundled Sample Debug"
            subtitle = bundledPresentation?.subtitle ?? "Run the bundled sample to inspect direct file inference."
            if let bundledPresentation, let panelDetails = bundledPresentation.details, !panelDetails.isEmpty {
                details = [panelDetails, bundledSnapshot?.details].compactMap { $0 }.joined(separator: "\n\n")
            } else {
                details = bundledSnapshot?.details ?? "No bundled debug sample is available yet."
            }
            showEmptyState = bundledSnapshot == nil
        }

        eyebrowLabel.text = selectedSource == .selectedTarget ? "DEBUG CAMERA" : "DEBUG BUNDLED"
        titleLabel.text = title
        subtitleLabel.text = subtitle
        previewImageView.image = snapshot?.previewImage
        previewCard.isHidden = snapshot?.previewImage == nil
        previewImageView.isHidden = snapshot?.previewImage == nil
        detailsTextView.text = details
        emptyLabel.isHidden = !showEmptyState
    }

    @objc private func runButtonPressed() {
        onRunBundledSample?()
    }

    @objc private func sourceChanged() {
        let source: DiagnosisDebugSource = sourceControl.selectedSegmentIndex == 1 ? .bundledSample : .selectedTarget
        onSelectedSource?(source)
    }

    private func configure() {
        view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        view.tintColor = UIColor(red: 0.49, green: 0.84, blue: 0.33, alpha: 0.96)

        eyebrowLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        eyebrowLabel.textColor = UIColor(red: 0.73, green: 0.95, blue: 0.64, alpha: 0.95)

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 2

        sourceControl.selectedSegmentIndex = 0
        sourceControl.selectedSegmentTintColor = UIColor(red: 0.49, green: 0.84, blue: 0.33, alpha: 0.96)
        sourceControl.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        sourceControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.84)], for: .normal)
        sourceControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        sourceControl.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)

        runButton.configuration = .filled()
        runButton.configuration?.title = "Run Bundled Sample"
        runButton.configuration?.cornerStyle = .capsule
        runButton.configuration?.baseBackgroundColor = UIColor(red: 0.49, green: 0.84, blue: 0.33, alpha: 0.96)
        runButton.configuration?.baseForegroundColor = .black
        runButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        runButton.addTarget(self, action: #selector(runButtonPressed), for: .touchUpInside)

        previewCard.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        previewCard.layer.cornerRadius = 18
        previewCard.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        previewCard.layer.borderWidth = 1
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.contentMode = .scaleAspectFit
        previewImageView.backgroundColor = .clear
        previewImageView.layer.cornerRadius = 14
        previewImageView.clipsToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        detailsTextView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        detailsTextView.textColor = UIColor.white.withAlphaComponent(0.86)
        detailsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsTextView.isEditable = false
        detailsTextView.layer.cornerRadius = 18
        detailsTextView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        detailsTextView.layer.borderWidth = 1
        detailsTextView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        emptyLabel.numberOfLines = 2
        emptyLabel.textAlignment = .center
        emptyLabel.text = "Run a bundled sample or scan a target to inspect debug details."
        emptyLabel.isHidden = true

        previewCard.addSubview(previewImageView)

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, subtitleLabel, sourceControl, runButton, previewCard, detailsTextView, emptyLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),

            previewCard.heightAnchor.constraint(equalToConstant: 220),
            previewImageView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16),
            previewImageView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16),
            previewImageView.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 16),
            previewImageView.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -16),
            detailsTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }
}
