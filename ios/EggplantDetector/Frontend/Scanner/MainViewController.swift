import AVFoundation
import CoreImage
import UIKit

final class MainViewController: UIViewController {
    private enum BundledDebugClearReason {
        case targetSelected
        case userReset
        case modeChanged
        case cameraReset
        case screenExit
    }

    private let previewView = CameraPreviewView()
    private let frozenImageView = UIImageView()
    private let targetOverlayView = TargetOverlayView()
    private let topCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let actionDock = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let brandLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["Live", "Photo"])
    private let modeHelperLabel = UILabel()
    private let debugSampleButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private let overlayView = PredictionView()
    private let cameraService = CameraService()
    private let classifier = try? TFLiteClassifier()
    private let selectedTargetController = SelectedTargetController()
    private let plantDetector: PlantDetector = PlaceholderPlantDetector()
    private let plantTracker: PlantTracker = ManualLockPlantTracker()
    private let previewImageContext = CIContext()
    private let captureButton = UIButton(type: .system)
    private let saveSummaryButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private lazy var actionStack = UIStackView(arrangedSubviews: [captureButton, saveSummaryButton, retakeButton])

    private let initialCaptureMode: CaptureMode
    private let showsDismissButton: Bool
    private var captureMode: CaptureMode
    private var lastLiveInferenceAt: Date = .distantPast
    private var lastPhotoAssistAt: Date = .distantPast
    private var lastRenderedState: DiagnosisState?
    private var lastRenderedMode: CaptureMode?
    private var liveStabilizer = LiveResultStabilizer()
    private var liveInferenceInFlight = false
    private var currentLiveCardState: LiveCardState?
    private let diagnosisSummaryStore = try? DiagnosisSummaryStore()
    private var latestCameraDebugSnapshot: DiagnosisDebugSnapshot?
    private var latestBundledDebugSnapshot: DiagnosisDebugSnapshot?
    private var displayedDebugSnapshot: DiagnosisDebugSnapshot?
    private var bundledDebugPresentation: BundledDebugPresentation?
    private weak var debugPanelController: DiagnosisDebugPanelViewController?
    private var debugPanelSource: DiagnosisDebugSource = .selectedTarget
    private var isFrozen = false
    private var pendingPhotoCapture = false
    private var overlayBottomToDockConstraint: NSLayoutConstraint?
    private var overlayBottomToSafeAreaConstraint: NSLayoutConstraint?

    init(initialCaptureMode: CaptureMode = .photo, showsDismissButton: Bool = false) {
        self.initialCaptureMode = initialCaptureMode
        self.showsDismissButton = showsDismissButton
        self.captureMode = initialCaptureMode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = previewView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        cameraService.delegate = self
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            renderTargetState()
        } else {
            render(state: .needsRetake(reason: .capturePhoto))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraService.start(in: previewView)
        animateChromeIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraService.refreshPreviewLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clearPinnedBundledDebug(reason: .screenExit)
        resetLiveAnalysisState()
        cameraService.stop()
    }

    private var isDebugModeEnabled: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private func configureUI() {
        view.backgroundColor = .black
        frozenImageView.translatesAutoresizingMaskIntoConstraints = false
        topCard.translatesAutoresizingMaskIntoConstraints = false
        actionDock.translatesAutoresizingMaskIntoConstraints = false
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        targetOverlayView.translatesAutoresizingMaskIntoConstraints = false
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        saveSummaryButton.translatesAutoresizingMaskIntoConstraints = false
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        debugSampleButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeHelperLabel.translatesAutoresizingMaskIntoConstraints = false
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        frozenImageView.contentMode = .scaleAspectFill
        frozenImageView.isHidden = true
        frozenImageView.alpha = 0
        view.clipsToBounds = true

        topCard.layer.cornerRadius = 18
        topCard.clipsToBounds = true
        topCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        topCard.layer.borderWidth = 1
        topCard.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.10)

        actionDock.layer.cornerRadius = 20
        actionDock.clipsToBounds = true
        actionDock.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        actionDock.layer.borderWidth = 1
        actionDock.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.12)

        brandLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        brandLabel.textColor = .white
        brandLabel.text = "EggplantDetector"

        modeControl.selectedSegmentIndex = initialCaptureMode == .live ? 0 : 1
        modeControl.selectedSegmentTintColor = UIColor(red: 0.48, green: 0.78, blue: 0.35, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.86)], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        modeHelperLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modeHelperLabel.textColor = UIColor.white.withAlphaComponent(0.76)
        modeHelperLabel.numberOfLines = 1
        modeHelperLabel.text = "Freeze one frame for a steadier read."
        modeHelperLabel.isHidden = true

        debugSampleButton.configuration = .bordered()
        debugSampleButton.configuration?.title = "Debug"
        debugSampleButton.configuration?.cornerStyle = .capsule
        debugSampleButton.configuration?.baseForegroundColor = .white
        debugSampleButton.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.04)
        debugSampleButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        debugSampleButton.isHidden = !isDebugModeEnabled
        debugSampleButton.addTarget(self, action: #selector(debugPressed), for: .touchUpInside)

        dismissButton.configuration = .plain()
        dismissButton.configuration?.image = UIImage(systemName: "xmark")
        dismissButton.configuration?.baseForegroundColor = .white
        dismissButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        dismissButton.isHidden = !showsDismissButton
        dismissButton.addTarget(self, action: #selector(dismissPressed), for: .touchUpInside)

        captureButton.configuration = .filled()
        captureButton.configuration?.title = "Capture"
        captureButton.configuration?.cornerStyle = .capsule
        captureButton.configuration?.baseBackgroundColor = UIColor(red: 0.49, green: 0.84, blue: 0.33, alpha: 0.96)
        captureButton.configuration?.baseForegroundColor = .black
        captureButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        captureButton.addTarget(self, action: #selector(capturePressed), for: .touchUpInside)

        saveSummaryButton.configuration = .bordered()
        saveSummaryButton.configuration?.title = "Save Summary"
        saveSummaryButton.configuration?.cornerStyle = .capsule
        saveSummaryButton.configuration?.baseForegroundColor = .white
        saveSummaryButton.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.04)
        saveSummaryButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        saveSummaryButton.isHidden = true
        saveSummaryButton.addTarget(self, action: #selector(saveSummaryPressed), for: .touchUpInside)

        retakeButton.configuration = .bordered()
        retakeButton.configuration?.title = "Retake"
        retakeButton.configuration?.cornerStyle = .capsule
        retakeButton.configuration?.baseForegroundColor = .white
        retakeButton.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.04)
        retakeButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        retakeButton.isHidden = true
        retakeButton.addTarget(self, action: #selector(retakePressed), for: .touchUpInside)

        actionStack.axis = .horizontal
        actionStack.spacing = 8
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var controlRowViews: [UIView] = []
        if showsDismissButton {
            controlRowViews.append(dismissButton)
        }
        controlRowViews.append(contentsOf: [brandLabel, spacer, modeControl])
        if isDebugModeEnabled {
            controlRowViews.append(debugSampleButton)
        }
        let controlRow = UIStackView(arrangedSubviews: controlRowViews)
        controlRow.axis = .horizontal
        controlRow.spacing = 8
        controlRow.alignment = .center
        debugSampleButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topStack = UIStackView(arrangedSubviews: [controlRow, modeHelperLabel])
        topStack.axis = .vertical
        topStack.spacing = 4
        topStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(frozenImageView)
        view.addSubview(targetOverlayView)
        view.addSubview(topCard)
        topCard.contentView.addSubview(topStack)
        view.addSubview(actionDock)
        actionDock.contentView.addSubview(actionStack)
        view.addSubview(overlayView)

        overlayBottomToDockConstraint = overlayView.bottomAnchor.constraint(equalTo: actionDock.topAnchor, constant: -12)
        overlayBottomToSafeAreaConstraint = overlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)

        NSLayoutConstraint.activate([
            frozenImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frozenImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frozenImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frozenImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            targetOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            targetOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            targetOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            targetOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            topStack.leadingAnchor.constraint(equalTo: topCard.contentView.leadingAnchor, constant: 12),
            topStack.trailingAnchor.constraint(equalTo: topCard.contentView.trailingAnchor, constant: -12),
            topStack.topAnchor.constraint(equalTo: topCard.contentView.topAnchor, constant: 10),
            topStack.bottomAnchor.constraint(equalTo: topCard.contentView.bottomAnchor, constant: -10),

            actionDock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            actionDock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            actionDock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionDock.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            actionStack.leadingAnchor.constraint(equalTo: actionDock.contentView.leadingAnchor, constant: 8),
            actionStack.trailingAnchor.constraint(equalTo: actionDock.contentView.trailingAnchor, constant: -8),
            actionStack.topAnchor.constraint(equalTo: actionDock.contentView.topAnchor, constant: 6),
            actionStack.bottomAnchor.constraint(equalTo: actionDock.contentView.bottomAnchor, constant: -6),

            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            overlayView.heightAnchor.constraint(greaterThanOrEqualToConstant: 82),
            overlayView.heightAnchor.constraint(lessThanOrEqualToConstant: 144),

            captureButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            saveSummaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
            retakeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])

        overlayBottomToDockConstraint?.isActive = true

        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handlePreviewTap(_:)))
            targetOverlayView.addGestureRecognizer(tapRecognizer)
            captureButton.isHidden = true
            retakeButton.configuration?.title = "Reset target"
        }

        [topCard, overlayView, actionDock].forEach {
            $0.alpha = 0
            $0.transform = CGAffineTransform(translationX: 0, y: 18)
        }
    }

    @objc private func modeChanged() {
        clearPinnedBundledDebug(reason: .modeChanged)
        captureMode = modeControl.selectedSegmentIndex == 0 ? .live : .photo
        resetLiveAnalysisState()
        resetFrozenState()
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            renderTargetState()
            return
        }
        let state: DiagnosisState = captureMode == .live
            ? .needsRetake(reason: .frameSingleLeaf)
            : .needsRetake(reason: .capturePhoto)
        render(state: state)
    }

    @objc private func capturePressed() {
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            guard captureMode == .photo else { return }
            guard case .selected = selectedTargetController.state else {
                renderTargetState()
                return
            }
            pendingPhotoCapture = true
            hideModeHelper()
            return
        }
        guard captureMode == .photo else { return }
        pendingPhotoCapture = true
        hideModeHelper()
    }

    @objc private func saveSummaryPressed() {
        guard captureMode == .live else { return }
        guard case let .selected(target) = selectedTargetController.state else { return }
        guard let liveCardState = currentLiveCardState,
              let summary = makeSavedDiagnosisSummary(from: liveCardState, target: target) else {
            showModeHelper("Wait for a stable live result before saving.")
            return
        }
        guard let diagnosisSummaryStore else {
            showModeHelper("Local summary storage is unavailable.")
            return
        }

        do {
            // Future export hook: attach annotated image export from the same stable live result if needed later.
            let savedURL = try diagnosisSummaryStore.save(summary)
            showModeHelper("Saved summary to \(savedURL.lastPathComponent).")
        } catch {
            showModeHelper("Could not save summary locally.")
        }
    }

    @objc private func debugPressed() {
        guard isDebugModeEnabled else { return }
        let panel = DiagnosisDebugPanelViewController()
        panel.onDismiss = { [weak self] in
            self?.debugPanelController = nil
        }
        panel.onRunBundledSample = { [weak self] in
            self?.runBundledDebugSample()
        }
        panel.onSelectedSource = { [weak self] source in
            self?.debugPanelSource = source
            self?.updateDebugPanelIfPresented()
        }
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        debugPanelController = panel
        present(panel, animated: true) { [weak self] in
            self?.updateDebugPanelIfPresented()
        }
    }

    @objc private func dismissPressed() {
        dismiss(animated: true)
    }

    private func runBundledDebugSample() {
        guard isDebugModeEnabled else { return }
        debugSampleButton.isEnabled = false
        debugPanelController?.setRunning(true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let classifier = self.classifier else {
                let snapshot = DiagnosisDebugSnapshot(
                    sourceType: .bundledSample,
                    sourceLabel: "Source: Bundled Sample",
                    previewImage: nil,
                    details: "No bundled debug sample found."
                )
                let presentation = BundledDebugPresentation(
                    eyebrow: "DEBUG SAMPLE",
                    title: "Bundled sample unavailable",
                    subtitle: "The bundled sample could not be loaded for inference.",
                    details: nil
                )
                DispatchQueue.main.async {
                    self.publishBundledDebugSnapshot(snapshot)
                    self.bundledDebugPresentation = presentation
                    self.debugPanelSource = .bundledSample
                    self.updateDebugPanelIfPresented()
                    self.debugSampleButton.isEnabled = true
                    self.debugPanelController?.setRunning(false)
                }
                return
            }

            let snapshot: DiagnosisDebugSnapshot
            let presentation: BundledDebugPresentation
            if let sample = loadBundledDebugSampleImage() {
                do {
                    let prepared = try classifier.prepareImage(sample.image)
                    let result = try classifier.classify(preparedFrame: prepared)
                    let state = DiagnosisRules.photoDiagnosis(assessment: prepared.assessment, result: result)
                    snapshot = self.buildDebugSnapshot(
                        sourceType: .bundledSample,
                        sourceLabel: "Source: Bundled Sample",
                        fileLabel: sample.filename,
                        sourceImageSize: sample.image.size,
                        prepared: prepared,
                        result: result,
                        state: state,
                        mode: .photo
                    )
                    presentation = makeBundledDebugPresentation(
                        state: state,
                        assessment: prepared.assessment,
                        result: result,
                        filename: sample.filename
                    )
                } catch {
                    snapshot = DiagnosisDebugSnapshot(
                        sourceType: .bundledSample,
                        sourceLabel: "Source: Bundled Sample",
                        previewImage: nil,
                        details: "Bundled sample inference failed: \(error.localizedDescription)"
                    )
                    presentation = BundledDebugPresentation(
                        eyebrow: "DEBUG SAMPLE",
                        title: "Bundled sample inference failed",
                        subtitle: "The sample image loaded, but inference did not complete.",
                        details: nil
                    )
                }
            } else {
                snapshot = DiagnosisDebugSnapshot(
                    sourceType: .bundledSample,
                    sourceLabel: "Source: Bundled Sample",
                    previewImage: nil,
                    details: "No bundled debug sample found."
                )
                presentation = BundledDebugPresentation(
                    eyebrow: "DEBUG SAMPLE",
                    title: "Bundled sample unavailable",
                    subtitle: "No bundled debug sample found.",
                    details: nil
                )
            }

            DispatchQueue.main.async {
                self.publishBundledDebugSnapshot(snapshot)
                self.bundledDebugPresentation = presentation
                self.debugPanelSource = .bundledSample
                self.updateDebugPanelIfPresented()
                self.debugSampleButton.isEnabled = true
                self.debugPanelController?.setRunning(false)
            }
        }
    }

    @objc private func retakePressed() {
        clearPinnedBundledDebug(reason: .userReset)
        resetLiveAnalysisState()
        clearCameraDebugSnapshot()
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            resetFrozenState()
            selectedTargetController.resetTarget(reason: .reset)
            renderTargetState()
            return
        }
        resetFrozenState()
        render(state: .needsRetake(reason: .capturePhoto))
    }

    @objc private func handlePreviewTap(_ recognizer: UITapGestureRecognizer) {
        guard TargetSelectionContract.isPhase1ManualTargetingEnabled else { return }
        clearPinnedBundledDebug(reason: .targetSelected)
        resetLiveAnalysisState()
        clearCameraDebugSnapshot()
        resetFrozenState()
        let point = recognizer.location(in: targetOverlayView)
        let selection = PreviewTargetMapper.manualSelection(for: point, in: targetOverlayView.bounds)
        selectedTargetController.selectManualTarget(box: selection)
        renderTargetState()
    }

    private func resetFrozenState() {
        isFrozen = false
        pendingPhotoCapture = false
        frozenImageView.image = nil
        frozenImageView.isHidden = true
        frozenImageView.alpha = 0
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            switch selectedTargetController.state {
            case .selected:
                if captureMode == .live {
                    applyLiveActionLayout(for: currentLiveCardState ?? .analyzing)
                } else {
                    applyPhotoSelectedActionLayout()
                }
            case .none, .lost:
                applyNoTargetActionLayout()
            }
            return
        }
        captureButton.isHidden = captureMode == .live
        saveSummaryButton.isHidden = true
        retakeButton.isHidden = true
        hideModeHelper()
    }

    private func render(state: DiagnosisState) {
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            guard case .selected = selectedTargetController.state else {
                renderTargetState()
                return
            }

            if captureMode == .live {
                render(liveCardState: currentLiveCardState ?? .analyzing)
                return
            }

            if state != lastRenderedState || captureMode != lastRenderedMode {
                overlayView.render(state: state, mode: captureMode)
                lastRenderedState = state
                lastRenderedMode = captureMode
            }

            targetOverlayView.targetState = selectedTargetController.state
            applyPhotoSelectedActionLayout()
            hideModeHelper()
            view.layoutIfNeeded()
            return
        }

        if state != lastRenderedState || captureMode != lastRenderedMode {
            overlayView.render(state: state, mode: captureMode)
            lastRenderedState = state
            lastRenderedMode = captureMode
        }

        let showActionDock = captureMode == .photo
        actionDock.isHidden = !showActionDock
        overlayBottomToDockConstraint?.isActive = showActionDock
        overlayBottomToSafeAreaConstraint?.isActive = !showActionDock

        captureButton.isHidden = captureMode == .live || isFrozen
        saveSummaryButton.isHidden = true
        retakeButton.isHidden = captureMode == .live || !isFrozen
        hideModeHelper()

        view.layoutIfNeeded()
    }

    private func render(liveCardState: LiveCardState) {
        currentLiveCardState = liveCardState

        guard TargetSelectionContract.isPhase1ManualTargetingEnabled,
              case .selected = selectedTargetController.state else {
            renderTargetState()
            return
        }

        lastRenderedState = nil
        lastRenderedMode = nil
        targetOverlayView.targetState = selectedTargetController.state
        applyLiveActionLayout(for: liveCardState)
        hideModeHelper()
        overlayView.render(liveCardState: liveCardState, isDebugMode: false)
        view.layoutIfNeeded()
    }

    private func renderTargetState() {
        let targetState = selectedTargetController.state
        targetOverlayView.targetState = targetState
        let hasSelectedTarget: Bool
        switch targetState {
        case .selected:
            hasSelectedTarget = true
        case .lost, .none:
            hasSelectedTarget = false
        }
        if !hasSelectedTarget {
            resetLiveAnalysisState()
            clearCameraDebugSnapshot()
        }
        if hasSelectedTarget, captureMode == .live {
            overlayView.render(liveCardState: currentLiveCardState ?? .analyzing, isDebugMode: false)
        } else {
            overlayView.render(targetState: targetState, mode: captureMode)
        }
        lastRenderedState = nil
        lastRenderedMode = nil

        switch targetState {
        case .selected:
            hideModeHelper()
        case .lost:
            hideModeHelper()
        case .none:
            hideModeHelper()
        }

        switch targetState {
        case .none, .lost:
            applyNoTargetActionLayout()
        case .selected:
            if captureMode == .live {
                applyLiveActionLayout(for: currentLiveCardState ?? .analyzing)
            } else {
                applyPhotoSelectedActionLayout()
            }
        }
        view.layoutIfNeeded()
    }

    private func previewImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = previewImageContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func buildDebugSnapshot(
        sourceType: DiagnosisDebugSource,
        sourceLabel: String,
        fileLabel: String,
        sourceImageSize: CGSize,
        prepared: PreparedFrame,
        result: ClassificationResult?,
        state: DiagnosisState,
        mode: CaptureMode
    ) -> DiagnosisDebugSnapshot {
        let details = [
            "File: \(fileLabel)",
            "Source image: \(Int(sourceImageSize.width))x\(Int(sourceImageSize.height))",
            "Classifier input: \(Int(prepared.displayImage.size.width))x\(Int(prepared.displayImage.size.height))",
            DiagnosisDebugTrace.rawTopResults(result),
            DiagnosisDebugTrace.assessmentSummary(prepared.assessment),
            DiagnosisDebugTrace.decisionPath(mode: mode, assessment: prepared.assessment, result: result, state: state)
        ].joined(separator: "\n\n")

        return DiagnosisDebugSnapshot(
            sourceType: sourceType,
            sourceLabel: sourceLabel,
            previewImage: prepared.displayImage,
            details: details
        )
    }

    private func publishCameraDebugSnapshot(_ snapshot: DiagnosisDebugSnapshot) {
        latestCameraDebugSnapshot = snapshot
        if displayedDebugSnapshot?.sourceType != .bundledSample {
            displayedDebugSnapshot = snapshot
        }
        updateDebugPanelIfPresented()
    }

    private func publishBundledDebugSnapshot(_ snapshot: DiagnosisDebugSnapshot) {
        latestBundledDebugSnapshot = snapshot
        displayedDebugSnapshot = snapshot
        updateDebugPanelIfPresented()
    }

    private func clearPinnedBundledDebug(reason: BundledDebugClearReason) {
        _ = reason
        bundledDebugPresentation = nil
        latestBundledDebugSnapshot = nil
        if displayedDebugSnapshot?.sourceType == .bundledSample {
            displayedDebugSnapshot = latestCameraDebugSnapshot
        }
        if debugPanelSource == .bundledSample {
            debugPanelSource = .selectedTarget
        }
        updateDebugPanelIfPresented()
    }

    private func resetLiveAnalysisState() {
        currentLiveCardState = nil
        liveInferenceInFlight = false
        liveStabilizer.reset()
        lastLiveInferenceAt = .distantPast
    }

    private func showModeHelper(_ text: String) {
        modeHelperLabel.text = text
        modeHelperLabel.isHidden = false
    }

    private func hideModeHelper() {
        modeHelperLabel.isHidden = true
    }

    private func applyNoTargetActionLayout() {
        captureButton.isHidden = true
        saveSummaryButton.isHidden = true
        retakeButton.isHidden = true
        actionDock.isHidden = true
        overlayBottomToDockConstraint?.isActive = false
        overlayBottomToSafeAreaConstraint?.isActive = true
    }

    private func applyPhotoSelectedActionLayout() {
        actionDock.isHidden = false
        overlayBottomToDockConstraint?.isActive = true
        overlayBottomToSafeAreaConstraint?.isActive = false
        captureButton.isHidden = isFrozen
        saveSummaryButton.isHidden = true
        retakeButton.isHidden = false
    }

    private func applyLiveActionLayout(for liveCardState: LiveCardState) {
        actionDock.isHidden = false
        overlayBottomToDockConstraint?.isActive = true
        overlayBottomToSafeAreaConstraint?.isActive = false
        captureButton.isHidden = true
        retakeButton.isHidden = false

        switch liveCardState {
        case .confirmed:
            saveSummaryButton.isHidden = false
        case .analyzing, .guidanceNoTarget, .stabilityHint, .guidance, .guardBlocked, .uncertain, .unavailable:
            saveSummaryButton.isHidden = true
        }
    }

    private func clearCameraDebugSnapshot() {
        latestCameraDebugSnapshot = nil
        if displayedDebugSnapshot?.sourceType == .selectedTarget {
            displayedDebugSnapshot = latestBundledDebugSnapshot
        }
        updateDebugPanelIfPresented()
    }

    private func updateDebugPanelIfPresented() {
        guard let debugPanelController else { return }

        let cameraSnapshot = latestCameraDebugSnapshot
        let bundledSnapshot = latestBundledDebugSnapshot
        let bundledPresentation = bundledDebugPresentation
        let selectedSource: DiagnosisDebugSource

        if debugPanelSource == .bundledSample, bundledSnapshot != nil {
            selectedSource = .bundledSample
        } else if cameraSnapshot != nil {
            selectedSource = .selectedTarget
        } else if bundledSnapshot != nil {
            selectedSource = .bundledSample
        } else {
            selectedSource = .selectedTarget
        }

        debugPanelController.render(
            selectedSource: selectedSource,
            cameraSnapshot: cameraSnapshot,
            bundledSnapshot: bundledSnapshot,
            bundledPresentation: bundledPresentation
        )
    }

    private func animateChromeIn() {
        let targets: [UIView] = [topCard, overlayView, actionDock]
        for (index, chrome) in targets.enumerated() {
            UIView.animate(
                withDuration: 0.45,
                delay: 0.05 * Double(index),
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.2,
                options: [.curveEaseOut]
            ) {
                chrome.alpha = 1
                chrome.transform = .identity
            }
        }
    }
}

extension MainViewController: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer) {
        guard !isFrozen else { return }

        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            // Future eggplant detector hook: replace PlaceholderPlantDetector with a real detector that returns plant candidates.
            let candidatePlants = plantDetector.detectCandidates(in: pixelBuffer)
            // Future tracking hook: replace ManualLockPlantTracker with a real tracker that updates the selected target.
            let updatedState = plantTracker.updateSelectedTarget(
                currentState: selectedTargetController.state,
                candidates: candidatePlants
            )
            if updatedState != selectedTargetController.state {
                selectedTargetController.applyTrackedState(updatedState)
                DispatchQueue.main.async { [weak self] in
                    self?.renderTargetState()
                }
            }

            guard case let .selected(target) = selectedTargetController.state else { return }
            guard let classifier else { return }
            let liveCrop = target.box.expanded(scale: TargetSelectionContract.liveDiagnosisCropExpansion)

            if captureMode == .live {
                guard !liveInferenceInFlight else { return }
                guard Date().timeIntervalSince(lastLiveInferenceAt) >= ModelContract.liveInferenceInterval else {
                    return
                }
                lastLiveInferenceAt = Date()
                liveInferenceInFlight = true
                defer { liveInferenceInFlight = false }

                do {
                    let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer, crop: liveCrop)
                    let result = try classifier.classify(preparedFrame: prepared)
                    // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
                    let state = DiagnosisRules.liveDiagnosis(assessment: prepared.assessment, result: result)
                    let topResult = result.topResults.first
                    let liveSnapshot = LiveAnalysisSnapshot(
                        diagnosisState: state,
                        assessment: prepared.assessment,
                        topLabel: topResult?.label,
                        topConfidence: topResult?.confidence
                    )
                    let liveCardState = liveStabilizer.consume(snapshot: liveSnapshot)
                    self.publishCameraDebugSnapshot(self.buildDebugSnapshot(
                        sourceType: .selectedTarget,
                        sourceLabel: "Source: Camera Selected Crop",
                        fileLabel: "Selected crop from active camera target",
                        sourceImageSize: prepared.displayImage.size,
                        prepared: prepared,
                        result: result,
                        state: state,
                        mode: .live
                    ))
                    NSLog(
                        "EggplantDiagnosis mode=live brightness=%.3f leafRatio=%.3f centerLeafRatio=%.3f state=%@",
                        prepared.assessment.meanBrightness,
                        prepared.assessment.likelyLeafRatio,
                        prepared.assessment.centerLeafRatio,
                        String(describing: state)
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.render(liveCardState: liveCardState)
                    }
                } catch {
                    let liveCardState = liveStabilizer.consumeUnavailable()
                    DispatchQueue.main.async { [weak self] in
                        self?.render(liveCardState: liveCardState)
                    }
                }
                return
            }

            if pendingPhotoCapture {
                pendingPhotoCapture = false
                isFrozen = true
                let frozenPreviewImage = previewImage(from: pixelBuffer)
                do {
                    let photoCrop = target.box.expanded(scale: TargetSelectionContract.photoDiagnosisCropExpansion)
                    let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer, crop: photoCrop)
                    let result = try classifier.classify(preparedFrame: prepared)
                    // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
                    let state = DiagnosisRules.photoDiagnosis(assessment: prepared.assessment, result: result)
                    self.publishCameraDebugSnapshot(self.buildDebugSnapshot(
                        sourceType: .selectedTarget,
                        sourceLabel: "Source: Camera Selected Crop",
                        fileLabel: "Selected crop from active camera target",
                        sourceImageSize: prepared.displayImage.size,
                        prepared: prepared,
                        result: result,
                        state: state,
                        mode: .photo
                    ))
                    NSLog(
                        "EggplantDiagnosis mode=photo brightness=%.3f leafRatio=%.3f centerLeafRatio=%.3f state=%@",
                        prepared.assessment.meanBrightness,
                        prepared.assessment.likelyLeafRatio,
                        prepared.assessment.centerLeafRatio,
                        String(describing: state)
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.frozenImageView.image = frozenPreviewImage
                        self?.frozenImageView.isHidden = frozenPreviewImage == nil
                        UIView.animate(withDuration: 0.2) {
                            self?.frozenImageView.alpha = frozenPreviewImage == nil ? 0 : 1
                        }
                        self?.render(state: state)
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.isFrozen = false
                        self?.render(state: .needsRetake(reason: .frameSingleLeaf))
                    }
                }
            }
            return
        }

        guard let classifier else { return }

        if captureMode == .live {
            guard Date().timeIntervalSince(lastLiveInferenceAt) >= ModelContract.liveInferenceInterval else {
                return
            }
            lastLiveInferenceAt = Date()

            do {
                let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer)
                let result = try classifier.classify(preparedFrame: prepared)
                let state = DiagnosisRules.liveDiagnosis(assessment: prepared.assessment, result: result)
                NSLog(
                    "EggplantDiagnosis mode=live brightness=%.3f leafRatio=%.3f centerLeafRatio=%.3f state=%@",
                    prepared.assessment.meanBrightness,
                    prepared.assessment.likelyLeafRatio,
                    prepared.assessment.centerLeafRatio,
                    String(describing: state)
                )
                DispatchQueue.main.async { [weak self] in
                    self?.render(state: state)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.render(state: .needsRetake(reason: .frameSingleLeaf))
                }
            }
            return
        }

        if pendingPhotoCapture {
            pendingPhotoCapture = false
            isFrozen = true
            do {
                let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer)
                let result = try classifier.classify(preparedFrame: prepared)
                let state = DiagnosisRules.photoDiagnosis(assessment: prepared.assessment, result: result)
                NSLog(
                    "EggplantDiagnosis mode=photo brightness=%.3f leafRatio=%.3f centerLeafRatio=%.3f state=%@",
                    prepared.assessment.meanBrightness,
                    prepared.assessment.likelyLeafRatio,
                    prepared.assessment.centerLeafRatio,
                    String(describing: state)
                )
                DispatchQueue.main.async { [weak self] in
                    self?.frozenImageView.image = prepared.displayImage
                    self?.frozenImageView.isHidden = false
                    UIView.animate(withDuration: 0.2) {
                        self?.frozenImageView.alpha = 1
                    }
                    self?.render(state: state)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.isFrozen = false
                    self?.render(state: .needsRetake(reason: .frameSingleLeaf))
                }
            }
            return
        }

        guard Date().timeIntervalSince(lastPhotoAssistAt) >= 0.5 else { return }
        lastPhotoAssistAt = Date()
        do {
            let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer)
            let state = DiagnosisRules.photoAssist(assessment: prepared.assessment)
            DispatchQueue.main.async { [weak self] in
                self?.render(state: state)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.render(state: .needsRetake(reason: .frameSingleLeaf))
            }
        }
    }

    func cameraService(_ service: CameraService, didFail error: Error) {
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            clearPinnedBundledDebug(reason: .cameraReset)
            resetLiveAnalysisState()
            clearCameraDebugSnapshot()
            selectedTargetController.resetTarget(reason: .cameraInterrupted)
            DispatchQueue.main.async { [weak self] in
                self?.renderTargetState()
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.render(state: .needsRetake(reason: .frameSingleLeaf))
            self?.showModeHelper(error.localizedDescription)
        }
    }
}
