package com.example.eggplantdetector

import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.RectF
import java.util.UUID
import kotlin.math.min
import kotlin.math.roundToInt

object TargetSelectionContract {
    const val isPhase1ManualTargetingEnabled = true
    const val manualSelectionBoxSizeRatio = 0.28f
}

data class NormalizedRect(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float
) {
    init {
        require(left <= right) { "left must be <= right" }
        require(top <= bottom) { "top must be <= bottom" }
    }

    companion object {
        fun fromCenter(
            centerX: Float,
            centerY: Float,
            widthRatio: Float,
            heightRatio: Float
        ): NormalizedRect {
            val clampedWidth = widthRatio.coerceIn(0.01f, 1f)
            val clampedHeight = heightRatio.coerceIn(0.01f, 1f)
            val maxLeft = (1f - clampedWidth).coerceAtLeast(0f)
            val maxTop = (1f - clampedHeight).coerceAtLeast(0f)
            val left = (centerX - clampedWidth / 2f).coerceIn(0f, maxLeft)
            val top = (centerY - clampedHeight / 2f).coerceIn(0f, maxTop)
            return NormalizedRect(
                left = left,
                top = top,
                right = (left + clampedWidth).coerceIn(left, 1f),
                bottom = (top + clampedHeight).coerceIn(top, 1f)
            )
        }
    }
}

data class PlantCandidate(
    val id: String,
    val box: NormalizedRect,
    val confidence: Float
)

enum class TargetSelectionSource {
    MANUAL_TAP,
    TRACKER
}

data class SelectedPlantTarget(
    val id: String,
    val box: NormalizedRect,
    val source: TargetSelectionSource,
    val updatedAtMs: Long
)

enum class TargetLossReason {
    RESET,
    MODE_CHANGED,
    CAMERA_INTERRUPTED
}

sealed interface SelectedTargetState {
    object None : SelectedTargetState

    data class Selected(
        val target: SelectedPlantTarget
    ) : SelectedTargetState

    data class Lost(
        val previousTarget: SelectedPlantTarget?,
        val reason: TargetLossReason
    ) : SelectedTargetState
}

interface PlantDetector {
    fun detectCandidates(bitmap: Bitmap): List<PlantCandidate>
}

class PlaceholderPlantDetector : PlantDetector {
    override fun detectCandidates(bitmap: Bitmap): List<PlantCandidate> = emptyList()
}

interface PlantTracker {
    fun updateSelectedTarget(
        currentState: SelectedTargetState,
        candidates: List<PlantCandidate>
    ): SelectedTargetState
}

class ManualLockPlantTracker : PlantTracker {
    override fun updateSelectedTarget(
        currentState: SelectedTargetState,
        candidates: List<PlantCandidate>
    ): SelectedTargetState = currentState
}

class SelectedTargetController(
    private val nowMs: () -> Long = { System.currentTimeMillis() }
) {
    var state: SelectedTargetState = SelectedTargetState.None
        private set

    fun selectManualTarget(box: NormalizedRect): SelectedTargetState {
        state = SelectedTargetState.Selected(
            target = SelectedPlantTarget(
                id = UUID.randomUUID().toString(),
                box = box,
                source = TargetSelectionSource.MANUAL_TAP,
                updatedAtMs = nowMs()
            )
        )
        return state
    }

    fun resetTarget(reason: TargetLossReason = TargetLossReason.RESET): SelectedTargetState {
        state = when (val currentState = state) {
            is SelectedTargetState.Selected -> SelectedTargetState.Lost(currentState.target, reason)
            is SelectedTargetState.Lost -> SelectedTargetState.Lost(currentState.previousTarget, reason)
            SelectedTargetState.None -> SelectedTargetState.None
        }
        return state
    }

    fun applyTrackedState(updatedState: SelectedTargetState): SelectedTargetState {
        state = updatedState
        return state
    }
}

object PreviewTargetMapper {
    fun analysisSquare(viewWidth: Float, viewHeight: Float): RectF {
        val size = min(viewWidth, viewHeight)
        val left = (viewWidth - size) / 2f
        val top = (viewHeight - size) / 2f
        return RectF(left, top, left + size, top + size)
    }

    fun manualSelectionForTap(
        tapX: Float,
        tapY: Float,
        viewWidth: Float,
        viewHeight: Float,
        boxSizeRatio: Float = TargetSelectionContract.manualSelectionBoxSizeRatio
    ): NormalizedRect {
        val square = analysisSquare(viewWidth, viewHeight)
        val clampedX = tapX.coerceIn(square.left, square.right)
        val clampedY = tapY.coerceIn(square.top, square.bottom)
        val normalizedX = ((clampedX - square.left) / square.width()).coerceIn(0f, 1f)
        val normalizedY = ((clampedY - square.top) / square.height()).coerceIn(0f, 1f)
        return NormalizedRect.fromCenter(
            centerX = normalizedX,
            centerY = normalizedY,
            widthRatio = boxSizeRatio,
            heightRatio = boxSizeRatio
        )
    }

    fun viewRectFor(box: NormalizedRect, viewWidth: Float, viewHeight: Float): RectF {
        val square = analysisSquare(viewWidth, viewHeight)
        return RectF(
            square.left + (box.left * square.width()),
            square.top + (box.top * square.height()),
            square.left + (box.right * square.width()),
            square.top + (box.bottom * square.height())
        )
    }
}

object SelectedTargetCropper {
    fun analysisSquareRect(imageWidth: Int, imageHeight: Int): Rect {
        val size = min(imageWidth, imageHeight)
        val left = (imageWidth - size) / 2
        val top = (imageHeight - size) / 2
        return Rect(left, top, left + size, top + size)
    }

    fun pixelRectFor(box: NormalizedRect, imageWidth: Int, imageHeight: Int): Rect {
        val square = analysisSquareRect(imageWidth, imageHeight)
        val squareWidth = square.width().toFloat()
        val squareHeight = square.height().toFloat()
        val left = (square.left + (box.left * squareWidth)).roundToInt().coerceIn(0, imageWidth - 1)
        val top = (square.top + (box.top * squareHeight)).roundToInt().coerceIn(0, imageHeight - 1)
        val right = (square.left + (box.right * squareWidth)).roundToInt().coerceIn(left + 1, imageWidth)
        val bottom = (square.top + (box.bottom * squareHeight)).roundToInt().coerceIn(top + 1, imageHeight)
        return Rect(left, top, right, bottom)
    }

    fun cropBitmap(bitmap: Bitmap, box: NormalizedRect): Bitmap {
        val pixelRect = pixelRectFor(box, bitmap.width, bitmap.height)
        return Bitmap.createBitmap(
            bitmap,
            pixelRect.left,
            pixelRect.top,
            pixelRect.width(),
            pixelRect.height()
        )
    }
}
