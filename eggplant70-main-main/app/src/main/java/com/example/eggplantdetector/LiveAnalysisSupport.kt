package com.example.eggplantdetector

data class LiveAnalysisSnapshot(
    val diagnosisState: DiagnosisState,
    val assessment: FrameAssessment,
    val topLabel: String?,
    val topConfidence: Float?
) {
    val leafGuardPassed: Boolean =
        assessment.likelyLeafRatio >= ModelContract.minLeafRatio &&
            assessment.centerLeafRatio >= ModelContract.minCenterLeafRatio
}

sealed interface LiveDisplaySignature {
    data class Confirmed(val label: String) : LiveDisplaySignature
    data class Uncertain(val reason: DiagnosisReason, val topLabel: String?) : LiveDisplaySignature
    data class Guidance(val reason: DiagnosisReason, val topLabel: String?) : LiveDisplaySignature
    data class Blocked(val reason: DiagnosisReason) : LiveDisplaySignature
    data object Unavailable : LiveDisplaySignature
}

sealed interface LiveCardState {
    data object GuidanceNoTarget : LiveCardState
    data object Analyzing : LiveCardState
    data object StabilityHint : LiveCardState
    data class Guidance(val snapshot: LiveAnalysisSnapshot, val reason: DiagnosisReason) : LiveCardState
    data class GuardBlocked(val snapshot: LiveAnalysisSnapshot, val reason: DiagnosisReason) : LiveCardState
    data class Confirmed(
        val snapshot: LiveAnalysisSnapshot,
        val label: String,
        val confidence: Float
    ) : LiveCardState

    data class Uncertain(val snapshot: LiveAnalysisSnapshot, val reason: DiagnosisReason) : LiveCardState
    data object Unavailable : LiveCardState
}

data class LiveDebugSummary(
    val topLabel: String,
    val topConfidence: Float?,
    val leafRatio: Float,
    val centerLeafRatio: Float,
    val leafGuardPassed: Boolean,
    val finalDiagnosisState: String
)

data class LiveStabilizerConfig(
    val promotionFrameCount: Int = 2,
    val stabilityHintAcceptedAttemptThreshold: Int = 3
) {
    val normalizedPromotionFrameCount: Int = promotionFrameCount.coerceAtLeast(1)
    val normalizedStabilityHintAcceptedAttemptThreshold: Int =
        stabilityHintAcceptedAttemptThreshold.coerceAtLeast(1)
}

class LiveResultStabilizer(
    val config: LiveStabilizerConfig = LiveStabilizerConfig()
) {
    var promotedCardState: LiveCardState? = null
        private set
    var promotedSignature: LiveDisplaySignature? = null
        private set
    var acceptedAttemptCount: Int = 0
        private set

    private var pendingSignature: LiveDisplaySignature? = null
    private var pendingSnapshot: LiveAnalysisSnapshot? = null
    private var pendingMatchCount: Int = 0

    fun reset() {
        promotedCardState = null
        promotedSignature = null
        acceptedAttemptCount = 0
        pendingSignature = null
        pendingSnapshot = null
        pendingMatchCount = 0
    }

    fun consume(snapshot: LiveAnalysisSnapshot): LiveCardState {
        acceptedAttemptCount += 1

        val signature = signature(snapshot)
        val promotedState = promotedState(snapshot)

        if (promotedSignature == signature) {
            promotedCardState = promotedState
            clearPendingCandidate()
            acceptedAttemptCount = 0
            return promotedState
        }

        if (promotedSignature == null && promotesImmediatelyWithoutStableResult(signature)) {
            promotedSignature = signature
            promotedCardState = promotedState
            clearPendingCandidate()
            acceptedAttemptCount = 0
            return promotedState
        }

        registerCandidate(signature, snapshot)?.let { return it }

        if (
            promotedSignature == null &&
            acceptedAttemptCount >= config.normalizedStabilityHintAcceptedAttemptThreshold
        ) {
            return LiveCardState.StabilityHint
        }

        return promotedCardState ?: LiveCardState.Analyzing
    }

    fun consumeUnavailable(): LiveCardState {
        if (promotedSignature == LiveDisplaySignature.Unavailable) {
            clearPendingCandidate()
            return LiveCardState.Unavailable
        }

        registerCandidate(LiveDisplaySignature.Unavailable, null)?.let { return it }

        return promotedCardState ?: LiveCardState.Analyzing
    }

    private fun registerCandidate(
        signature: LiveDisplaySignature,
        snapshot: LiveAnalysisSnapshot?
    ): LiveCardState? {
        if (pendingSignature == signature) {
            pendingMatchCount += 1
            pendingSnapshot = snapshot
        } else {
            pendingSignature = signature
            pendingSnapshot = snapshot
            pendingMatchCount = 1
        }

        if (pendingMatchCount < config.normalizedPromotionFrameCount) {
            return null
        }

        val promotedState = promotedState(signature, pendingSnapshot)
        promotedSignature = signature
        promotedCardState = promotedState
        clearPendingCandidate()
        acceptedAttemptCount = 0
        return promotedState
    }

    private fun clearPendingCandidate() {
        pendingSignature = null
        pendingSnapshot = null
        pendingMatchCount = 0
    }

    companion object {
        private fun promotesImmediatelyWithoutStableResult(signature: LiveDisplaySignature): Boolean {
            return signature is LiveDisplaySignature.Blocked
        }

        fun signature(snapshot: LiveAnalysisSnapshot): LiveDisplaySignature {
            return when (val state = snapshot.diagnosisState) {
                is DiagnosisState.Confirmed -> LiveDisplaySignature.Confirmed(state.label)
                is DiagnosisState.Uncertain -> LiveDisplaySignature.Uncertain(
                    reason = state.reason,
                    topLabel = snapshot.topLabel
                )

                is DiagnosisState.NeedsRetake -> {
                    if (isGuardBlocked(state.reason)) {
                        LiveDisplaySignature.Blocked(state.reason)
                    } else {
                        LiveDisplaySignature.Guidance(
                            reason = state.reason,
                            topLabel = snapshot.topLabel
                        )
                    }
                }
            }
        }

        fun promotedState(snapshot: LiveAnalysisSnapshot): LiveCardState {
            return when (val state = snapshot.diagnosisState) {
                is DiagnosisState.Confirmed -> LiveCardState.Confirmed(
                    snapshot = snapshot,
                    label = state.label,
                    confidence = state.confidence
                )

                is DiagnosisState.Uncertain -> LiveCardState.Uncertain(
                    snapshot = snapshot,
                    reason = state.reason
                )

                is DiagnosisState.NeedsRetake -> {
                    if (isGuardBlocked(state.reason)) {
                        LiveCardState.GuardBlocked(snapshot, state.reason)
                    } else {
                        LiveCardState.Guidance(snapshot, state.reason)
                    }
                }
            }
        }

        fun promotedState(
            signature: LiveDisplaySignature,
            snapshot: LiveAnalysisSnapshot?
        ): LiveCardState {
            return when (signature) {
                is LiveDisplaySignature.Confirmed -> {
                    val resolvedSnapshot = snapshot ?: return LiveCardState.Unavailable
                    val confidence = resolvedSnapshot.topConfidence ?: return LiveCardState.Unavailable
                    LiveCardState.Confirmed(resolvedSnapshot, signature.label, confidence)
                }

                is LiveDisplaySignature.Uncertain -> {
                    val resolvedSnapshot = snapshot ?: return LiveCardState.Unavailable
                    LiveCardState.Uncertain(resolvedSnapshot, signature.reason)
                }

                is LiveDisplaySignature.Guidance -> {
                    val resolvedSnapshot = snapshot ?: return LiveCardState.Unavailable
                    LiveCardState.Guidance(resolvedSnapshot, signature.reason)
                }

                is LiveDisplaySignature.Blocked -> {
                    val resolvedSnapshot = snapshot ?: return LiveCardState.Unavailable
                    LiveCardState.GuardBlocked(resolvedSnapshot, signature.reason)
                }

                LiveDisplaySignature.Unavailable -> LiveCardState.Unavailable
            }
        }

        fun debugSummary(snapshot: LiveAnalysisSnapshot): LiveDebugSummary {
            return LiveDebugSummary(
                topLabel = snapshot.topLabel ?: "No result",
                topConfidence = snapshot.topConfidence,
                leafRatio = snapshot.assessment.likelyLeafRatio,
                centerLeafRatio = snapshot.assessment.centerLeafRatio,
                leafGuardPassed = snapshot.leafGuardPassed,
                finalDiagnosisState = diagnosisStateSummary(snapshot.diagnosisState)
            )
        }

        fun diagnosisStateSummary(diagnosisState: DiagnosisState): String {
            return when (diagnosisState) {
                is DiagnosisState.Confirmed -> "confirmed (${diagnosisState.label})"
                is DiagnosisState.Uncertain -> "uncertain (${diagnosisState.reason})"
                is DiagnosisState.NeedsRetake -> "needsRetake (${diagnosisState.reason})"
            }
        }

        fun isGuardBlocked(reason: DiagnosisReason): Boolean {
            return when (reason) {
                DiagnosisReason.NO_LEAF_DETECTED,
                DiagnosisReason.INCREASE_LIGHT,
                DiagnosisReason.REDUCE_GLARE -> true

                DiagnosisReason.CAPTURE_PHOTO,
                DiagnosisReason.FRAME_SINGLE_LEAF,
                DiagnosisReason.LOW_CONFIDENCE,
                DiagnosisReason.AMBIGUOUS -> false
            }
        }
    }
}
