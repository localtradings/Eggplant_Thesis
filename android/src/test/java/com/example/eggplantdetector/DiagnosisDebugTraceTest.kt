package com.example.eggplantdetector

import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosisDebugTraceTest {

    @Test
    fun rawTopResultsHandlesMissingScores() {
        val trace = DiagnosisDebugTrace.rawTopResults(result = null)

        assertTrue(trace.contains("no model scores returned"))
    }

    @Test
    fun decisionPathShowsLeafGuardFailure() {
        val assessment = FrameAssessment(
            meanBrightness = 0.5f,
            likelyLeafRatio = 0.1f,
            centerLeafRatio = 0.1f
        )
        val state = DiagnosisState.NeedsRetake(DiagnosisReason.NO_LEAF_DETECTED)

        val trace = DiagnosisDebugTrace.decisionPath(
            mode = CaptureMode.PHOTO,
            assessment = assessment,
            result = null,
            state = state
        )

        assertTrue(trace.contains("leaf guard"))
        assertTrue(trace.contains("needsRetake NO_LEAF_DETECTED"))
    }
}
