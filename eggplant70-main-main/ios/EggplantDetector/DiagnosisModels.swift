import Foundation

enum CaptureMode: Equatable {
    case live
    case photo
}

enum DiagnosisReason: Equatable {
    case capturePhoto
    case noLeafDetected
    case frameSingleLeaf
    case increaseLight
    case reduceGlare
    case lowConfidence
    case ambiguous

    var title: String {
        switch self {
        case .capturePhoto:
            return "Capture a photo to diagnose"
        case .noLeafDetected:
            return "No leaf detected yet"
        case .frameSingleLeaf:
            return "Frame one leaf more clearly"
        case .increaseLight:
            return "Increase lighting"
        case .reduceGlare:
            return "Reduce glare"
        case .lowConfidence:
            return "Retake for a stronger signal"
        case .ambiguous:
            return "Possible label conflict"
        }
    }

    var message: String {
        switch self {
        case .capturePhoto:
            return "Freeze one frame for a steadier read."
        case .noLeafDetected:
            return "Point the camera at a clear eggplant leaf."
        case .frameSingleLeaf:
            return "Move closer and keep one leaf centered."
        case .increaseLight:
            return "Try brighter, more even lighting."
        case .reduceGlare:
            return "Step away from glare and try again."
        case .lowConfidence:
            return "Capture a sharper, closer view."
        case .ambiguous:
            return "The top labels are too close. Retake first."
        }
    }
}

enum DiagnosisState: Equatable {
    case confirmed(label: String, confidence: Float, topResults: [PredictionScore])
    case uncertain(topResults: [PredictionScore], reason: DiagnosisReason)
    case needsRetake(reason: DiagnosisReason)
}

struct FrameAssessment {
    let meanBrightness: Float
    let likelyLeafRatio: Float
    let centerLeafRatio: Float
}

enum ModelContract {
    static let minConfidence: Float = 0.72
    static let ambiguityMargin: Float = 0.12
    static let minBrightness: Float = 0.18
    static let maxBrightness: Float = 0.92
    static let minLeafRatio: Float = 0.18
    static let minCenterLeafRatio: Float = 0.18
    static let liveInferenceInterval: TimeInterval = 0.7
    static let preprocessingSummary = "Center crop to a square, resize to the model input size, convert to RGB, normalize to 0..1 for float models, and decode one score per class."
}

enum DiagnosisRules {
    static func liveDiagnosis(
        assessment: FrameAssessment,
        result: ClassificationResult?
    ) -> DiagnosisState {
        if let brightnessState = brightnessGuard(assessment) {
            return brightnessState
        }

        guard let result, let best = result.topResults.first else {
            return .needsRetake(reason: .frameSingleLeaf)
        }

        let second = result.topResults.dropFirst().first
        if best.confidence < ModelContract.minConfidence {
            return .needsRetake(reason: .frameSingleLeaf)
        }

        if let second, best.confidence - second.confidence < ModelContract.ambiguityMargin {
            return .uncertain(topResults: result.topResults, reason: .ambiguous)
        }

        return .confirmed(label: best.label, confidence: best.confidence, topResults: result.topResults)
    }

    static func photoAssist(assessment: FrameAssessment) -> DiagnosisState {
        if let brightnessState = brightnessGuard(assessment) {
            return brightnessState
        }

        return .needsRetake(reason: .capturePhoto)
    }

    static func photoDiagnosis(
        assessment: FrameAssessment,
        result: ClassificationResult?
    ) -> DiagnosisState {
        if let brightnessState = brightnessGuard(assessment) {
            return brightnessState
        }

        guard let result, let best = result.topResults.first else {
            return .needsRetake(reason: .frameSingleLeaf)
        }

        let second = result.topResults.dropFirst().first
        if best.confidence < ModelContract.minConfidence {
            return .uncertain(topResults: result.topResults, reason: .lowConfidence)
        }

        if let second, best.confidence - second.confidence < ModelContract.ambiguityMargin {
            return .uncertain(topResults: result.topResults, reason: .ambiguous)
        }

        return .confirmed(label: best.label, confidence: best.confidence, topResults: result.topResults)
    }

    private static func brightnessGuard(_ assessment: FrameAssessment) -> DiagnosisState? {
        if assessment.likelyLeafRatio < ModelContract.minLeafRatio ||
            assessment.centerLeafRatio < ModelContract.minCenterLeafRatio {
            return .needsRetake(reason: .noLeafDetected)
        }

        if assessment.meanBrightness < ModelContract.minBrightness {
            return .needsRetake(reason: .increaseLight)
        }

        if assessment.meanBrightness > ModelContract.maxBrightness {
            return .needsRetake(reason: .reduceGlare)
        }

        return nil
    }
}

enum DiagnosisDebugTrace {
    static func rawTopResults(_ result: ClassificationResult?) -> String {
        let topResults = result?.topResults ?? []
        guard !topResults.isEmpty else {
            return "raw top3: no model scores returned"
        }

        let lines = topResults.prefix(3).enumerated().map { index, prediction in
            "\(index + 1). \(prediction.label) = \(format(prediction.confidence))"
        }
        return (["raw top3:"] + lines).joined(separator: "\n")
    }

    static func assessmentSummary(_ assessment: FrameAssessment) -> String {
        "assessment: brightness=\(format(assessment.meanBrightness)), leafRatio=\(format(assessment.likelyLeafRatio)), centerLeafRatio=\(format(assessment.centerLeafRatio))"
    }

    static func decisionPath(
        mode: CaptureMode,
        assessment: FrameAssessment,
        result: ClassificationResult?,
        state: DiagnosisState
    ) -> String {
        var lines = ["preprocess: selected/source image -> square crop -> resize -> RGB -> model"]
        lines.append(
            "leaf guard: likelyLeafRatio \(format(assessment.likelyLeafRatio)) vs \(format(ModelContract.minLeafRatio)), centerLeafRatio \(format(assessment.centerLeafRatio)) vs \(format(ModelContract.minCenterLeafRatio))"
        )

        if assessment.likelyLeafRatio < ModelContract.minLeafRatio ||
            assessment.centerLeafRatio < ModelContract.minCenterLeafRatio {
            lines.append("decision: brightness guard failed -> \(stateSummary(state))")
            return lines.joined(separator: "\n")
        }

        lines.append(
            "brightness guard: mean \(format(assessment.meanBrightness)) in [\(format(ModelContract.minBrightness)), \(format(ModelContract.maxBrightness))]"
        )
        if assessment.meanBrightness < ModelContract.minBrightness ||
            assessment.meanBrightness > ModelContract.maxBrightness {
            lines.append("decision: brightness out of range -> \(stateSummary(state))")
            return lines.joined(separator: "\n")
        }

        guard let best = result?.topResults.first else {
            lines.append("decision: no top result returned -> \(stateSummary(state))")
            return lines.joined(separator: "\n")
        }

        let second = result?.topResults.dropFirst().first
        lines.append(
            "model: best=\(best.label) \(format(best.confidence)), second=\(second?.label ?? "none") \(format(second?.confidence ?? 0))"
        )
        lines.append(
            "\(mode == .live ? "live" : "photo") confidence rule: \(format(best.confidence)) vs \(format(ModelContract.minConfidence))"
        )

        if best.confidence < ModelContract.minConfidence {
            lines.append("decision: confidence below threshold -> \(stateSummary(state))")
            return lines.joined(separator: "\n")
        }

        if let second {
            let margin = best.confidence - second.confidence
            lines.append("ambiguity margin: \(format(margin)) vs \(format(ModelContract.ambiguityMargin))")
            if margin < ModelContract.ambiguityMargin {
                lines.append("decision: ambiguity margin failed -> \(stateSummary(state))")
                return lines.joined(separator: "\n")
            }
        }

        lines.append("decision: all guards passed -> \(stateSummary(state))")
        return lines.joined(separator: "\n")
    }

    private static func stateSummary(_ state: DiagnosisState) -> String {
        switch state {
        case let .confirmed(label, _, _):
            return "confirmed \(label)"
        case let .uncertain(_, reason):
            return "uncertain \(reason)"
        case let .needsRetake(reason):
            return "needsRetake \(reason)"
        }
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.4f", value)
    }
}
