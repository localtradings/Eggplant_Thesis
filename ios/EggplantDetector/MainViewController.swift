import AVFoundation
import CoreImage
import UIKit

final class MainViewController: UIViewController {
    private let previewView = CameraPreviewView()
    private let frozenImageView = UIImageView()
    private let targetOverlayView = TargetOverlayView()
    private let topCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let actionDock = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let brandLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["Live", "Photo"])
    private let modeHelperLabel = UILabel()
    private let overlayView = PredictionView()
    private let cameraService = CameraService()
    private let classifier = try? TFLiteClassifier()
    private let selectedTargetController = SelectedTargetController()
    private let plantDetector: PlantDetector = PlaceholderPlantDetector()
    private let plantTracker: PlantTracker = ManualLockPlantTracker()
    private let previewImageContext = CIContext()
    private let captureButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private lazy var actionStack = UIStackView(arrangedSubviews: [captureButton, retakeButton])

    private var captureMode: CaptureMode = .photo
    private var lastLiveInferenceAt: Date = .distantPast
    private var lastPhotoAssistAt: Date = .distantPast
    private var lastRenderedState: DiagnosisState?
    private var lastRenderedMode: CaptureMode?
    private var isFrozen = false
    private var pendingPhotoCapture = false
    private var overlayBottomToDockConstraint: NSLayoutConstraint?
    private var overlayBottomToSafeAreaConstraint: NSLayoutConstraint?

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
        cameraService.stop()
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
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeHelperLabel.translatesAutoresizingMaskIntoConstraints = false
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        frozenImageView.contentMode = .scaleAspectFill
        frozenImageView.isHidden = true
        frozenImageView.alpha = 0
        view.clipsToBounds = true

        topCard.layer.cornerRadius = 14
        topCard.clipsToBounds = true
        topCard.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        topCard.layer.borderWidth = 1

        actionDock.layer.cornerRadius = 18
        actionDock.clipsToBounds = true
        actionDock.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        actionDock.layer.borderWidth = 1

        brandLabel.font = .systemFont(ofSize: 13, weight: .bold)
        brandLabel.textColor = .white
        brandLabel.text = "EggplantDetector"

        modeControl.selectedSegmentIndex = 1
        modeControl.selectedSegmentTintColor = UIColor(red: 0.48, green: 0.78, blue: 0.35, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.86)], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        modeHelperLabel.font = .systemFont(ofSize: 9, weight: .medium)
        modeHelperLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        modeHelperLabel.numberOfLines = 1
        modeHelperLabel.text = "Freeze one frame for a steadier read."

        captureButton.configuration = .filled()
        captureButton.configuration?.title = "Capture"
        captureButton.configuration?.cornerStyle = .capsule
        captureButton.configuration?.baseBackgroundColor = UIColor(red: 0.49, green: 0.84, blue: 0.33, alpha: 0.96)
        captureButton.configuration?.baseForegroundColor = .black
        captureButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        captureButton.addTarget(self, action: #selector(capturePressed), for: .touchUpInside)

        retakeButton.configuration = .bordered()
        retakeButton.configuration?.title = "Retake"
        retakeButton.configuration?.cornerStyle = .capsule
        retakeButton.configuration?.baseForegroundColor = .white
        retakeButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        retakeButton.isHidden = true
        retakeButton.addTarget(self, action: #selector(retakePressed), for: .touchUpInside)

        actionStack.axis = .horizontal
        actionStack.spacing = 4
        actionStack.alignment = .center

        let topStack = UIStackView(arrangedSubviews: [brandLabel, modeControl, modeHelperLabel])
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

        let preferredTopWidth = topCard.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.58)
        preferredTopWidth.priority = .defaultHigh
        overlayBottomToDockConstraint = overlayView.bottomAnchor.constraint(equalTo: actionDock.topAnchor, constant: -10)
        overlayBottomToSafeAreaConstraint = overlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)

        NSLayoutConstraint.activate([
            frozenImageView.topAnchor.constraint(equalTo: view.topAnchor),
            frozenImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frozenImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frozenImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            targetOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            targetOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            targetOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            targetOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topCard.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            preferredTopWidth,
            topCard.widthAnchor.constraint(lessThanOrEqualToConstant: 244),

            topStack.leadingAnchor.constraint(equalTo: topCard.contentView.leadingAnchor, constant: 8),
            topStack.trailingAnchor.constraint(equalTo: topCard.contentView.trailingAnchor, constant: -8),
            topStack.topAnchor.constraint(equalTo: topCard.contentView.topAnchor, constant: 8),
            topStack.bottomAnchor.constraint(equalTo: topCard.contentView.bottomAnchor, constant: -8),

            actionDock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionDock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            actionDock.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            actionDock.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            actionDock.widthAnchor.constraint(lessThanOrEqualToConstant: 188),

            actionStack.leadingAnchor.constraint(equalTo: actionDock.contentView.leadingAnchor, constant: 4),
            actionStack.trailingAnchor.constraint(equalTo: actionDock.contentView.trailingAnchor, constant: -4),
            actionStack.topAnchor.constraint(equalTo: actionDock.contentView.topAnchor, constant: 4),
            actionStack.bottomAnchor.constraint(equalTo: actionDock.contentView.bottomAnchor, constant: -4),

            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            overlayView.heightAnchor.constraint(lessThanOrEqualToConstant: 78)
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
        captureMode = modeControl.selectedSegmentIndex == 0 ? .live : .photo
        resetFrozenState()
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            selectedTargetController.resetTarget(reason: .modeChanged)
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
            modeHelperLabel.text = "Analyzing only the selected target."
            return
        }
        guard captureMode == .photo else { return }
        pendingPhotoCapture = true
        modeHelperLabel.text = "Analyzing frame..."
    }

    @objc private func retakePressed() {
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
                captureButton.isHidden = captureMode == .live
                retakeButton.isHidden = false
                actionDock.isHidden = false
                overlayBottomToDockConstraint?.isActive = true
                overlayBottomToSafeAreaConstraint?.isActive = false
            case .none, .lost:
                captureButton.isHidden = true
                retakeButton.isHidden = true
                actionDock.isHidden = true
                overlayBottomToDockConstraint?.isActive = false
                overlayBottomToSafeAreaConstraint?.isActive = true
            }
            return
        }
        captureButton.isHidden = captureMode == .live
        retakeButton.isHidden = true
        modeHelperLabel.text = captureMode == .live
            ? "Center one leaf. Live scan updates softly."
            : "Freeze one frame for a steadier read."
    }

    private func render(state: DiagnosisState) {
        if TargetSelectionContract.isPhase1ManualTargetingEnabled {
            guard case .selected = selectedTargetController.state else {
                renderTargetState()
                return
            }

            if state != lastRenderedState || captureMode != lastRenderedMode {
                overlayView.render(state: state, mode: captureMode)
                lastRenderedState = state
                lastRenderedMode = captureMode
            }

            targetOverlayView.targetState = selectedTargetController.state
            actionDock.isHidden = false
            overlayBottomToDockConstraint?.isActive = true
            overlayBottomToSafeAreaConstraint?.isActive = false
            captureButton.isHidden = captureMode != .photo || isFrozen
            retakeButton.isHidden = false
            modeHelperLabel.text = captureMode == .live
                ? "Analyzing only the selected target."
                : (isFrozen ? "Selected target diagnosis ready. Reset to choose again." : "Capture to analyze only the selected target.")
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
        retakeButton.isHidden = captureMode == .live || !isFrozen
        if captureMode == .live {
            modeHelperLabel.text = "Center one leaf. Live scan updates softly."
        } else if isFrozen {
            modeHelperLabel.text = "Frozen frame ready."
        } else {
            modeHelperLabel.text = "Freeze one frame for a steadier read."
        }

        view.layoutIfNeeded()
    }

    private func renderTargetState() {
        let targetState = selectedTargetController.state
        targetOverlayView.targetState = targetState
        overlayView.render(targetState: targetState, mode: captureMode)
        lastRenderedState = nil
        lastRenderedMode = nil

        let hasSelectedTarget: Bool
        switch targetState {
        case .selected:
            hasSelectedTarget = true
            modeHelperLabel.text = captureMode == .live
                ? "Analyzing only the selected target."
                : "Capture to analyze only the selected target."
        case .lost:
            hasSelectedTarget = false
            modeHelperLabel.text = "Target lost. Tap again."
        case .none:
            hasSelectedTarget = false
            modeHelperLabel.text = "Tap one eggplant plant to begin"
        }

        captureButton.isHidden = !hasSelectedTarget || captureMode == .live || isFrozen
        retakeButton.isHidden = !hasSelectedTarget
        actionDock.isHidden = !hasSelectedTarget
        overlayBottomToDockConstraint?.isActive = hasSelectedTarget
        overlayBottomToSafeAreaConstraint?.isActive = !hasSelectedTarget
        view.layoutIfNeeded()
    }

    private func previewImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = previewImageContext.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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

            if captureMode == .live {
                guard Date().timeIntervalSince(lastLiveInferenceAt) >= ModelContract.liveInferenceInterval else {
                    return
                }
                lastLiveInferenceAt = Date()

                do {
                    let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer, crop: target.box)
                    let result = try classifier.classify(preparedFrame: prepared)
                    // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
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
                let frozenPreviewImage = previewImage(from: pixelBuffer)
                do {
                    let prepared = try classifier.prepareFrame(pixelBuffer: pixelBuffer, crop: target.box)
                    let result = try classifier.classify(preparedFrame: prepared)
                    // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
                    let state = DiagnosisRules.photoDiagnosis(assessment: prepared.assessment, result: result)
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
            selectedTargetController.resetTarget(reason: .cameraInterrupted)
            DispatchQueue.main.async { [weak self] in
                self?.renderTargetState()
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.render(state: .needsRetake(reason: .frameSingleLeaf))
            self?.modeHelperLabel.text = error.localizedDescription
        }
    }
}
