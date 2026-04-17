import CoreGraphics
import CoreVideo
import Foundation

enum TargetSelectionContract {
    static let isPhase1ManualTargetingEnabled = true
    static let manualSelectionBoxSizeRatio: CGFloat = 0.28
}

struct NormalizedRect: Equatable {
    let left: CGFloat
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat

    init(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        precondition(left <= right, "left must be <= right")
        precondition(top <= bottom, "top must be <= bottom")
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    static func fromCenter(
        centerX: CGFloat,
        centerY: CGFloat,
        widthRatio: CGFloat,
        heightRatio: CGFloat
    ) -> NormalizedRect {
        let clampedWidth = min(max(widthRatio, 0.01), 1)
        let clampedHeight = min(max(heightRatio, 0.01), 1)
        let maxLeft = max(1 - clampedWidth, 0)
        let maxTop = max(1 - clampedHeight, 0)
        let left = min(max(centerX - clampedWidth / 2, 0), maxLeft)
        let top = min(max(centerY - clampedHeight / 2, 0), maxTop)
        return NormalizedRect(
            left: left,
            top: top,
            right: min(max(left + clampedWidth, left), 1),
            bottom: min(max(top + clampedHeight, top), 1)
        )
    }
}

struct PlantCandidate: Equatable {
    let id: String
    let box: NormalizedRect
    let confidence: Float
}

enum TargetSelectionSource: Equatable {
    case manualTap
    case tracker
}

struct SelectedPlantTarget: Equatable {
    let id: String
    let box: NormalizedRect
    let source: TargetSelectionSource
    let updatedAt: Date
}

enum TargetLossReason: Equatable {
    case reset
    case modeChanged
    case cameraInterrupted
}

enum SelectedTargetState: Equatable {
    case none
    case selected(target: SelectedPlantTarget)
    case lost(previousTarget: SelectedPlantTarget?, reason: TargetLossReason)
}

protocol PlantDetector {
    func detectCandidates(in pixelBuffer: CVPixelBuffer) -> [PlantCandidate]
}

final class PlaceholderPlantDetector: PlantDetector {
    func detectCandidates(in pixelBuffer: CVPixelBuffer) -> [PlantCandidate] {
        []
    }
}

protocol PlantTracker {
    func updateSelectedTarget(
        currentState: SelectedTargetState,
        candidates: [PlantCandidate]
    ) -> SelectedTargetState
}

final class ManualLockPlantTracker: PlantTracker {
    func updateSelectedTarget(
        currentState: SelectedTargetState,
        candidates: [PlantCandidate]
    ) -> SelectedTargetState {
        currentState
    }
}

final class SelectedTargetController {
    private let now: () -> Date

    private(set) var state: SelectedTargetState = .none

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    func selectManualTarget(box: NormalizedRect) -> SelectedTargetState {
        state = .selected(
            target: SelectedPlantTarget(
                id: UUID().uuidString,
                box: box,
                source: .manualTap,
                updatedAt: now()
            )
        )
        return state
    }

    @discardableResult
    func resetTarget(reason: TargetLossReason = .reset) -> SelectedTargetState {
        switch state {
        case let .selected(target):
            state = .lost(previousTarget: target, reason: reason)
        case let .lost(previousTarget, _):
            state = .lost(previousTarget: previousTarget, reason: reason)
        case .none:
            state = .none
        }
        return state
    }

    @discardableResult
    func applyTrackedState(_ updatedState: SelectedTargetState) -> SelectedTargetState {
        state = updatedState
        return state
    }
}

enum PreviewTargetMapper {
    static func analysisSquare(in bounds: CGRect) -> CGRect {
        let size = min(bounds.width, bounds.height)
        let originX = bounds.midX - size / 2
        let originY = bounds.midY - size / 2
        return CGRect(x: originX, y: originY, width: size, height: size)
    }

    static func manualSelection(
        for point: CGPoint,
        in bounds: CGRect,
        boxSizeRatio: CGFloat = TargetSelectionContract.manualSelectionBoxSizeRatio
    ) -> NormalizedRect {
        let square = analysisSquare(in: bounds)
        let clampedX = min(max(point.x, square.minX), square.maxX)
        let clampedY = min(max(point.y, square.minY), square.maxY)
        let normalizedX = min(max((clampedX - square.minX) / square.width, 0), 1)
        let normalizedY = min(max((clampedY - square.minY) / square.height, 0), 1)
        return NormalizedRect.fromCenter(
            centerX: normalizedX,
            centerY: normalizedY,
            widthRatio: boxSizeRatio,
            heightRatio: boxSizeRatio
        )
    }

    static func viewRect(for box: NormalizedRect, in bounds: CGRect) -> CGRect {
        let square = analysisSquare(in: bounds)
        return CGRect(
            x: square.minX + box.left * square.width,
            y: square.minY + box.top * square.height,
            width: (box.right - box.left) * square.width,
            height: (box.bottom - box.top) * square.height
        )
    }
}
