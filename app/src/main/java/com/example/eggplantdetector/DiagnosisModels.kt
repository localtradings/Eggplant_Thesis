package com.example.eggplantdetector

enum class CaptureMode {
    LIVE,
    PHOTO
}

enum class DiagnosisReason {
    CAPTURE_PHOTO,
    NO_LEAF_DETECTED,
    FRAME_SINGLE_LEAF,
    INCREASE_LIGHT,
    REDUCE_GLARE,
    LOW_CONFIDENCE,
    AMBIGUOUS
}

sealed interface DiagnosisState {
    data class Confirmed(
        val label: String,
        val confidence: Float,
        val topResults: List<TFLiteImageClassifier.Prediction>
    ) : DiagnosisState

    data class Uncertain(
        val topResults: List<TFLiteImageClassifier.Prediction>,
        val reason: DiagnosisReason
    ) : DiagnosisState

    data class NeedsRetake(
        val reason: DiagnosisReason
    ) : DiagnosisState
}

data class FrameAssessment(
    val meanBrightness: Float,
    val likelyLeafRatio: Float,
    val centerLeafRatio: Float
)

object ModelContract {
    const val minConfidence = 0.72f
    const val ambiguityMargin = 0.12f
    const val minBrightness = 0.18f
    const val maxBrightness = 0.92f
    const val minLeafRatio = 0.22f
    const val minCenterLeafRatio = 0.18f
    const val liveInferenceIntervalMs = 700L

    const val preprocessingSummary =
        "Center crop to a square, resize to the model input size, convert to RGB, normalize to 0..1 for float models, and decode one score per class."
}

object DiagnosisRules {
    fun liveDiagnosis(
        assessment: FrameAssessment,
        result: TFLiteImageClassifier.ClassificationResult?
    ): DiagnosisState {
        brightnessGuard(assessment)?.let { return it }
        if (result == null || result.topResults.isEmpty()) {
            return DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF)
        }

        val best = result.topResults[0]
        val second = result.topResults.getOrNull(1)
        if (best.confidence < ModelContract.minConfidence) {
            return DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF)
        }

        if (second != null && best.confidence - second.confidence < ModelContract.ambiguityMargin) {
            return DiagnosisState.Uncertain(result.topResults, DiagnosisReason.AMBIGUOUS)
        }

        return DiagnosisState.Confirmed(best.label, best.confidence, result.topResults)
    }

    fun photoAssist(assessment: FrameAssessment): DiagnosisState {
        brightnessGuard(assessment)?.let { return it }
        return DiagnosisState.NeedsRetake(DiagnosisReason.CAPTURE_PHOTO)
    }

    fun photoDiagnosis(
        assessment: FrameAssessment,
        result: TFLiteImageClassifier.ClassificationResult?
    ): DiagnosisState {
        brightnessGuard(assessment)?.let { return it }
        if (result == null || result.topResults.isEmpty()) {
            return DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF)
        }

        val best = result.topResults[0]
        val second = result.topResults.getOrNull(1)
        if (best.confidence < ModelContract.minConfidence) {
            return DiagnosisState.Uncertain(result.topResults, DiagnosisReason.LOW_CONFIDENCE)
        }

        if (second != null && best.confidence - second.confidence < ModelContract.ambiguityMargin) {
            return DiagnosisState.Uncertain(result.topResults, DiagnosisReason.AMBIGUOUS)
        }

        return DiagnosisState.Confirmed(best.label, best.confidence, result.topResults)
    }

    private fun brightnessGuard(assessment: FrameAssessment): DiagnosisState.NeedsRetake? {
        if (
            assessment.likelyLeafRatio < ModelContract.minLeafRatio ||
            assessment.centerLeafRatio < ModelContract.minCenterLeafRatio
        ) {
            return DiagnosisState.NeedsRetake(DiagnosisReason.NO_LEAF_DETECTED)
        }

        return when {
            assessment.meanBrightness < ModelContract.minBrightness ->
                DiagnosisState.NeedsRetake(DiagnosisReason.INCREASE_LIGHT)

            assessment.meanBrightness > ModelContract.maxBrightness ->
                DiagnosisState.NeedsRetake(DiagnosisReason.REDUCE_GLARE)

            else -> null
        }
    }
}
