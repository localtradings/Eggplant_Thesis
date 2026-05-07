package com.example.eggplantdetector

import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosisRulesTest {

    @Test
    fun lowLightRequiresRetake() {
        val state = DiagnosisRules.liveDiagnosis(
            FrameAssessment(meanBrightness = 0.1f, likelyLeafRatio = 0.3f, centerLeafRatio = 0.3f),
            mockResult(0.95f, 0.03f, 0.02f)
        )

        assertTrue(state is DiagnosisState.NeedsRetake)
    }

    @Test
    fun ambiguousPredictionsStayUncertain() {
        val state = DiagnosisRules.photoDiagnosis(
            FrameAssessment(meanBrightness = 0.45f, likelyLeafRatio = 0.3f, centerLeafRatio = 0.3f),
            mockResult(0.74f, 0.68f, 0.10f)
        )

        assertTrue(state is DiagnosisState.Uncertain)
    }

    @Test
    fun confidentPredictionIsConfirmed() {
        val state = DiagnosisRules.photoDiagnosis(
            FrameAssessment(meanBrightness = 0.45f, likelyLeafRatio = 0.3f, centerLeafRatio = 0.3f),
            mockResult(0.92f, 0.06f, 0.02f)
        )

        assertTrue(state is DiagnosisState.Confirmed)
    }

    @Test
    fun backgroundWithoutLeafRequiresRetake() {
        val state = DiagnosisRules.photoDiagnosis(
            FrameAssessment(meanBrightness = 0.45f, likelyLeafRatio = 0.01f, centerLeafRatio = 0.01f),
            mockResult(0.96f, 0.03f, 0.01f)
        )

        assertTrue(state is DiagnosisState.NeedsRetake)
    }

    @Test
    fun offCenterGreenBackgroundRequiresRetake() {
        val state = DiagnosisRules.photoDiagnosis(
            FrameAssessment(meanBrightness = 0.45f, likelyLeafRatio = 0.22f, centerLeafRatio = 0.04f),
            mockResult(0.96f, 0.03f, 0.01f)
        )

        assertTrue(state is DiagnosisState.NeedsRetake)
    }

    private fun mockResult(first: Float, second: Float, third: Float): TFLiteImageClassifier.ClassificationResult {
        val topResults = listOf(
            TFLiteImageClassifier.Prediction("healthy", first),
            TFLiteImageClassifier.Prediction("leaf_spot", second),
            TFLiteImageClassifier.Prediction("wilt", third)
        )
        return TFLiteImageClassifier.ClassificationResult(
            label = topResults.first().label,
            confidence = topResults.first().confidence,
            topResults = topResults
        )
    }
}
