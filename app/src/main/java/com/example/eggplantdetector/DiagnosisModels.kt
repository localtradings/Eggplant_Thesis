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

object DiagnosisDebugTrace {
    fun rawTopResults(
        result: TFLiteImageClassifier.ClassificationResult?
    ): String {
        val topResults = result?.topResults.orEmpty()
        if (topResults.isEmpty()) {
            return "raw top3: no model scores returned"
        }

        return buildString {
            appendLine("raw top3:")
            topResults.take(3).forEachIndexed { index, prediction ->
                appendLine(
                    "${index + 1}. ${prediction.label} = ${"%.4f".format(prediction.confidence)}"
                )
            }
        }.trim()
    }

    fun assessmentSummary(assessment: FrameAssessment): String {
        return "assessment: brightness=${"%.4f".format(assessment.meanBrightness)}, " +
            "leafRatio=${"%.4f".format(assessment.likelyLeafRatio)}, " +
            "centerLeafRatio=${"%.4f".format(assessment.centerLeafRatio)}"
    }

    fun decisionPath(
        mode: CaptureMode,
        assessment: FrameAssessment,
        result: TFLiteImageClassifier.ClassificationResult?,
        state: DiagnosisState
    ): String {
        val lines = mutableListOf<String>()
        lines += "preprocess: selected/source image -> square crop -> resize -> RGB -> model"
        lines += "leaf guard: likelyLeafRatio ${formatFloat(assessment.likelyLeafRatio)} vs ${formatFloat(ModelContract.minLeafRatio)}, centerLeafRatio ${formatFloat(assessment.centerLeafRatio)} vs ${formatFloat(ModelContract.minCenterLeafRatio)}"

        if (
            assessment.likelyLeafRatio < ModelContract.minLeafRatio ||
            assessment.centerLeafRatio < ModelContract.minCenterLeafRatio
        ) {
            lines += "decision: brightness guard failed -> ${stateSummary(state)}"
            return lines.joinToString(separator = "\n")
        }

        lines += "brightness guard: mean ${formatFloat(assessment.meanBrightness)} in [${formatFloat(ModelContract.minBrightness)}, ${formatFloat(ModelContract.maxBrightness)}]"
        if (assessment.meanBrightness < ModelContract.minBrightness || assessment.meanBrightness > ModelContract.maxBrightness) {
            lines += "decision: brightness out of range -> ${stateSummary(state)}"
            return lines.joinToString(separator = "\n")
        }

        val best = result?.topResults?.getOrNull(0)
        val second = result?.topResults?.getOrNull(1)
        if (best == null) {
            lines += "decision: no top result returned -> ${stateSummary(state)}"
            return lines.joinToString(separator = "\n")
        }

        lines += "model: best=${best.label} ${formatFloat(best.confidence)}, second=${second?.label ?: "none"} ${formatFloat(second?.confidence ?: 0f)}"
        val confidenceLine = when (mode) {
            CaptureMode.LIVE ->
                "live confidence rule: ${formatFloat(best.confidence)} vs ${formatFloat(ModelContract.minConfidence)}"
            CaptureMode.PHOTO ->
                "photo confidence rule: ${formatFloat(best.confidence)} vs ${formatFloat(ModelContract.minConfidence)}"
        }
        lines += confidenceLine

        if (best.confidence < ModelContract.minConfidence) {
            lines += "decision: confidence below threshold -> ${stateSummary(state)}"
            return lines.joinToString(separator = "\n")
        }

        if (second != null) {
            val margin = best.confidence - second.confidence
            lines += "ambiguity margin: ${formatFloat(margin)} vs ${formatFloat(ModelContract.ambiguityMargin)}"
            if (margin < ModelContract.ambiguityMargin) {
                lines += "decision: ambiguity margin failed -> ${stateSummary(state)}"
                return lines.joinToString(separator = "\n")
            }
        }

        lines += "decision: all guards passed -> ${stateSummary(state)}"
        return lines.joinToString(separator = "\n")
    }

    private fun stateSummary(state: DiagnosisState): String {
        return when (state) {
            is DiagnosisState.Confirmed -> "confirmed ${state.label}"
            is DiagnosisState.Uncertain -> "uncertain ${state.reason}"
            is DiagnosisState.NeedsRetake -> "needsRetake ${state.reason}"
        }
    }

    private fun formatFloat(value: Float): String = "%.4f".format(value)
}
