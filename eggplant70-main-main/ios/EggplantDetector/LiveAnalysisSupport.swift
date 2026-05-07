import Foundation

struct LiveAnalysisSnapshot {
    let diagnosisState: DiagnosisState
    let assessment: FrameAssessment
    let topLabel: String?
    let topConfidence: Float?
    let leafGuardPassed: Bool

    init(
        diagnosisState: DiagnosisState,
        assessment: FrameAssessment,
        topLabel: String?,
        topConfidence: Float?
    ) {
        self.diagnosisState = diagnosisState
        self.assessment = assessment
        self.topLabel = topLabel
        self.topConfidence = topConfidence
        self.leafGuardPassed = assessment.likelyLeafRatio >= ModelContract.minLeafRatio &&
            assessment.centerLeafRatio >= ModelContract.minCenterLeafRatio
    }
}

enum LiveDisplaySignature: Equatable {
    case confirmed(label: String)
    case uncertain(reason: DiagnosisReason, topLabel: String?)
    case guidance(reason: DiagnosisReason, topLabel: String?)
    case blocked(reason: DiagnosisReason)
    case unavailable
}

enum LiveCardState {
    case guidanceNoTarget
    case analyzing
    case stabilityHint
    case guidance(snapshot: LiveAnalysisSnapshot, reason: DiagnosisReason)
    case guardBlocked(snapshot: LiveAnalysisSnapshot, reason: DiagnosisReason)
    case confirmed(snapshot: LiveAnalysisSnapshot, label: String, confidence: Float)
    case uncertain(snapshot: LiveAnalysisSnapshot, reason: DiagnosisReason)
    case unavailable
}

struct LiveDebugSummary {
    let topLabel: String
    let topConfidence: Float?
    let leafRatio: Float
    let centerLeafRatio: Float
    let leafGuardPassed: Bool
    let finalDiagnosisState: String
}

struct LiveStabilizerConfig: Equatable {
    let promotionFrameCount: Int
    let stabilityHintAcceptedAttemptThreshold: Int

    init(
        promotionFrameCount: Int = 2,
        stabilityHintAcceptedAttemptThreshold: Int = 3
    ) {
        self.promotionFrameCount = max(promotionFrameCount, 1)
        self.stabilityHintAcceptedAttemptThreshold = max(stabilityHintAcceptedAttemptThreshold, 1)
    }
}

struct LiveResultStabilizer {
    private(set) var promotedCardState: LiveCardState?
    private(set) var promotedSignature: LiveDisplaySignature?
    private(set) var acceptedAttemptCount = 0

    private var pendingSignature: LiveDisplaySignature?
    private var pendingSnapshot: LiveAnalysisSnapshot?
    private var pendingMatchCount = 0

    let config: LiveStabilizerConfig

    init(config: LiveStabilizerConfig = LiveStabilizerConfig()) {
        self.config = config
    }

    mutating func reset() {
        promotedCardState = nil
        promotedSignature = nil
        acceptedAttemptCount = 0
        pendingSignature = nil
        pendingSnapshot = nil
        pendingMatchCount = 0
    }

    mutating func consume(snapshot: LiveAnalysisSnapshot) -> LiveCardState {
        acceptedAttemptCount += 1

        let signature = Self.signature(for: snapshot)
        let promotedState = Self.promotedState(for: snapshot)

        if promotedSignature == signature {
            self.promotedCardState = promotedState
            clearPendingCandidate()
            acceptedAttemptCount = 0
            return promotedState
        }

        if promotedSignature == nil, Self.promotesImmediatelyWithoutStableResult(signature) {
            self.promotedSignature = signature
            self.promotedCardState = promotedState
            clearPendingCandidate()
            acceptedAttemptCount = 0
            return promotedState
        }

        let resolvedCardState = registerCandidate(signature: signature, snapshot: snapshot)
        if let resolvedCardState {
            return resolvedCardState
        }

        if promotedSignature == nil,
           acceptedAttemptCount >= config.stabilityHintAcceptedAttemptThreshold {
            return .stabilityHint
        }

        return promotedCardState ?? .analyzing
    }

    mutating func consumeUnavailable() -> LiveCardState {
        if promotedSignature == .unavailable {
            clearPendingCandidate()
            return .unavailable
        }

        let resolvedCardState = registerCandidate(signature: .unavailable, snapshot: nil)
        if let resolvedCardState {
            return resolvedCardState
        }

        return promotedCardState ?? .analyzing
    }

    private mutating func registerCandidate(
        signature: LiveDisplaySignature,
        snapshot: LiveAnalysisSnapshot?
    ) -> LiveCardState? {
        if pendingSignature == signature {
            pendingMatchCount += 1
            pendingSnapshot = snapshot
        } else {
            pendingSignature = signature
            pendingSnapshot = snapshot
            pendingMatchCount = 1
        }

        guard pendingMatchCount >= config.promotionFrameCount else {
            return nil
        }

        let promotedState = Self.promotedState(for: signature, snapshot: pendingSnapshot)
        promotedSignature = signature
        promotedCardState = promotedState
        clearPendingCandidate()
        acceptedAttemptCount = 0
        return promotedState
    }

    private mutating func clearPendingCandidate() {
        pendingSignature = nil
        pendingSnapshot = nil
        pendingMatchCount = 0
    }

    private static func promotesImmediatelyWithoutStableResult(_ signature: LiveDisplaySignature) -> Bool {
        if case .blocked = signature {
            return true
        }
        return false
    }

    static func signature(for snapshot: LiveAnalysisSnapshot) -> LiveDisplaySignature {
        switch snapshot.diagnosisState {
        case let .confirmed(label, _, _):
            return .confirmed(label: label)

        case let .uncertain(_, reason):
            return .uncertain(reason: reason, topLabel: snapshot.topLabel)

        case let .needsRetake(reason):
            if isGuardBlocked(reason) {
                return .blocked(reason: reason)
            }
            return .guidance(reason: reason, topLabel: snapshot.topLabel)
        }
    }

    static func promotedState(for snapshot: LiveAnalysisSnapshot) -> LiveCardState {
        switch snapshot.diagnosisState {
        case let .confirmed(label, confidence, _):
            return .confirmed(snapshot: snapshot, label: label, confidence: confidence)

        case let .uncertain(_, reason):
            return .uncertain(snapshot: snapshot, reason: reason)

        case let .needsRetake(reason):
            if isGuardBlocked(reason) {
                return .guardBlocked(snapshot: snapshot, reason: reason)
            }
            return .guidance(snapshot: snapshot, reason: reason)
        }
    }

    static func promotedState(
        for signature: LiveDisplaySignature,
        snapshot: LiveAnalysisSnapshot?
    ) -> LiveCardState {
        switch signature {
        case let .confirmed(label):
            guard let snapshot, let confidence = snapshot.topConfidence else {
                return .unavailable
            }
            return .confirmed(snapshot: snapshot, label: label, confidence: confidence)

        case let .uncertain(reason, _):
            guard let snapshot else { return .unavailable }
            return .uncertain(snapshot: snapshot, reason: reason)

        case let .guidance(reason, _):
            guard let snapshot else { return .unavailable }
            return .guidance(snapshot: snapshot, reason: reason)

        case let .blocked(reason):
            guard let snapshot else { return .unavailable }
            return .guardBlocked(snapshot: snapshot, reason: reason)

        case .unavailable:
            return .unavailable
        }
    }

    static func debugSummary(for snapshot: LiveAnalysisSnapshot) -> LiveDebugSummary {
        LiveDebugSummary(
            topLabel: snapshot.topLabel ?? "No result",
            topConfidence: snapshot.topConfidence,
            leafRatio: snapshot.assessment.likelyLeafRatio,
            centerLeafRatio: snapshot.assessment.centerLeafRatio,
            leafGuardPassed: snapshot.leafGuardPassed,
            finalDiagnosisState: diagnosisStateSummary(snapshot.diagnosisState)
        )
    }

    static func diagnosisStateSummary(_ diagnosisState: DiagnosisState) -> String {
        switch diagnosisState {
        case let .confirmed(label, _, _):
            return "confirmed (\(label))"
        case let .uncertain(_, reason):
            return "uncertain (\(reason))"
        case let .needsRetake(reason):
            return "needsRetake (\(reason))"
        }
    }

    static func isGuardBlocked(_ reason: DiagnosisReason) -> Bool {
        switch reason {
        case .noLeafDetected, .increaseLight, .reduceGlare:
            return true
        case .capturePhoto, .frameSingleLeaf, .lowConfidence, .ambiguous:
            return false
        }
    }
}
