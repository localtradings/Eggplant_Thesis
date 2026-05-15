import Foundation

func hasSaveableLiveSummary(_ currentLiveCardState: LiveCardState?) -> Bool {
    guard let currentLiveCardState else {
        return false
    }

    switch currentLiveCardState {
    case .confirmed:
        return true
    case .analyzing, .guidanceNoTarget, .stabilityHint, .guidance, .guardBlocked, .uncertain, .unavailable:
        return false
    }
}

func makeSavedDiagnosisSummary(
    from liveCardState: LiveCardState,
    target: SelectedPlantTarget
) -> SavedDiagnosisSummary? {
    switch liveCardState {
    case let .confirmed(snapshot, label, confidence):
        guard DiseaseCatalog.isSupportedLabel(label) else {
            return nil
        }
        return savedDiagnosisSummary(
            snapshot: snapshot,
            target: target,
            mode: .live,
            finalStateKind: .confirmed,
            diagnosisLabel: label,
            confidence: confidence,
            reason: nil
        )

    case .analyzing, .guidanceNoTarget, .stabilityHint, .guidance, .guardBlocked, .uncertain, .unavailable:
        return nil
    }
}

func makeSavedDiagnosisSummary(
    from diagnosisState: DiagnosisState,
    target: SelectedPlantTarget,
    mode: SavedCaptureMode,
    assessment: FrameAssessment
) -> SavedDiagnosisSummary? {
    guard case let .confirmed(label, confidence, topResults) = diagnosisState,
          DiseaseCatalog.isSupportedLabel(label) else {
        return nil
    }

    return SavedDiagnosisSummary(
        id: UUID(),
        createdAt: Date(),
        source: .cameraSelectedCrop,
        mode: mode,
        targetBox: SavedNormalizedRect(target.box),
        finalStateKind: .confirmed,
        diagnosisLabel: label,
        confidence: confidence,
        topLabel: topResults.first?.label,
        topConfidence: topResults.first?.confidence,
        meanBrightness: assessment.meanBrightness,
        likelyLeafRatio: assessment.likelyLeafRatio,
        centerLeafRatio: assessment.centerLeafRatio,
        leafGuardPassed: assessment.likelyLeafRatio >= ModelContract.minLeafRatio &&
            assessment.centerLeafRatio >= ModelContract.minCenterLeafRatio,
        reason: nil
    )
}

private func savedDiagnosisSummary(
    snapshot: LiveAnalysisSnapshot,
    target: SelectedPlantTarget,
    mode: SavedCaptureMode,
    finalStateKind: SavedDiagnosisStateKind,
    diagnosisLabel: String?,
    confidence: Float?,
    reason: String?
) -> SavedDiagnosisSummary {
    SavedDiagnosisSummary(
        id: UUID(),
        createdAt: Date(),
        source: .cameraSelectedCrop,
        mode: mode,
        targetBox: SavedNormalizedRect(target.box),
        finalStateKind: finalStateKind,
        diagnosisLabel: diagnosisLabel,
        confidence: confidence,
        topLabel: snapshot.topLabel,
        topConfidence: snapshot.topConfidence,
        meanBrightness: snapshot.assessment.meanBrightness,
        likelyLeafRatio: snapshot.assessment.likelyLeafRatio,
        centerLeafRatio: snapshot.assessment.centerLeafRatio,
        leafGuardPassed: snapshot.leafGuardPassed,
        reason: reason
    )
}
