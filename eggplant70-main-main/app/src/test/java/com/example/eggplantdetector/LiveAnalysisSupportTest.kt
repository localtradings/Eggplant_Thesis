package com.example.eggplantdetector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveAnalysisSupportTest {

    @Test
    fun blockedGuardPromotesImmediately() {
        val stabilizer = LiveResultStabilizer()
        val snapshot = snapshot(
            DiagnosisState.NeedsRetake(DiagnosisReason.NO_LEAF_DETECTED),
            leafRatio = 0.05f,
            centerLeafRatio = 0.05f
        )

        val state = stabilizer.consume(snapshot)

        assertTrue(state is LiveCardState.GuardBlocked)
        assertEquals(LiveDisplaySignature.Blocked(DiagnosisReason.NO_LEAF_DETECTED), stabilizer.promotedSignature)
    }

    @Test
    fun matchingConfirmedFramesPromoteAfterConfiguredCount() {
        val stabilizer = LiveResultStabilizer()
        val snapshot = snapshot(
            DiagnosisState.Confirmed(
                label = "healthy",
                confidence = 0.91f,
                topResults = listOf(TFLiteImageClassifier.Prediction("healthy", 0.91f))
            ),
            topLabel = "healthy",
            topConfidence = 0.91f
        )

        assertEquals(LiveCardState.Analyzing, stabilizer.consume(snapshot))
        val state = stabilizer.consume(snapshot)

        assertTrue(state is LiveCardState.Confirmed)
        assertEquals(LiveDisplaySignature.Confirmed("healthy"), stabilizer.promotedSignature)
    }

    @Test
    fun stabilityHintAppearsBeforeFirstPromotionAfterRepeatedAttempts() {
        val stabilizer = LiveResultStabilizer()
        val first = snapshot(
            DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF),
            topLabel = "healthy"
        )
        val second = snapshot(
            DiagnosisState.Uncertain(
                topResults = listOf(TFLiteImageClassifier.Prediction("leaf_spot", 0.74f)),
                reason = DiagnosisReason.AMBIGUOUS
            ),
            topLabel = "leaf_spot"
        )
        val third = snapshot(
            DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF),
            topLabel = "wilt"
        )

        assertEquals(LiveCardState.Analyzing, stabilizer.consume(first))
        assertEquals(LiveCardState.Analyzing, stabilizer.consume(second))
        assertEquals(LiveCardState.StabilityHint, stabilizer.consume(third))
    }

    @Test
    fun debugSummaryReportsLeafGuardOutcome() {
        val snapshot = snapshot(
            DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF),
            leafRatio = 0.19f,
            centerLeafRatio = 0.17f
        )

        val summary = LiveResultStabilizer.debugSummary(snapshot)

        assertFalse(summary.leafGuardPassed)
        assertEquals("No result", summary.topLabel)
    }

    private fun snapshot(
        state: DiagnosisState,
        leafRatio: Float = 0.4f,
        centerLeafRatio: Float = 0.4f,
        topLabel: String? = null,
        topConfidence: Float? = null
    ): LiveAnalysisSnapshot {
        return LiveAnalysisSnapshot(
            diagnosisState = state,
            assessment = FrameAssessment(
                meanBrightness = 0.5f,
                likelyLeafRatio = leafRatio,
                centerLeafRatio = centerLeafRatio
            ),
            topLabel = topLabel,
            topConfidence = topConfidence
        )
    }
}
