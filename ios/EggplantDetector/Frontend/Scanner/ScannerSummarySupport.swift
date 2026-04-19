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
        return savedDiagnosisSummary(
            snapshot: snapshot,
            target: target,
            finalStateKind: .confirmed,
            diagnosisLabel: label,
            confidence: confidence,
            reason: nil
        )

    case .analyzing, .guidanceNoTarget, .stabilityHint, .guidance, .guardBlocked, .uncertain, .unavailable:
        return nil
    }
}

private func savedDiagnosisSummary(
    snapshot: LiveAnalysisSnapshot,
    target: SelectedPlantTarget,
    finalStateKind: SavedDiagnosisStateKind,
    diagnosisLabel: String?,
    confidence: Float?,
    reason: String?
) -> SavedDiagnosisSummary {
    SavedDiagnosisSummary(
        id: UUID(),
        createdAt: Date(),
        source: .cameraSelectedCrop,
        mode: .live,
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
