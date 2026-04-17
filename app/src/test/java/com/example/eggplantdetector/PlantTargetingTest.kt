package com.example.eggplantdetector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlantTargetingTest {

    @Test
    fun firstTapCreatesSelectedState() {
        val controller = SelectedTargetController(nowMs = { 1234L })

        val state = controller.selectManualTarget(
            NormalizedRect.fromCenter(0.5f, 0.5f, 0.28f, 0.28f)
        )

        assertTrue(state is SelectedTargetState.Selected)
        val selected = state as SelectedTargetState.Selected
        assertEquals(TargetSelectionSource.MANUAL_TAP, selected.target.source)
        assertEquals(1234L, selected.target.updatedAtMs)
    }

    @Test
    fun secondTapReplacesSelectionAndStaysSelected() {
        val controller = SelectedTargetController(nowMs = { 1000L })
        val first = controller.selectManualTarget(
            NormalizedRect.fromCenter(0.25f, 0.25f, 0.28f, 0.28f)
        ) as SelectedTargetState.Selected

        val second = controller.selectManualTarget(
            NormalizedRect.fromCenter(0.75f, 0.75f, 0.28f, 0.28f)
        )

        assertTrue(second is SelectedTargetState.Selected)
        val selected = second as SelectedTargetState.Selected
        assertTrue(selected.target.box.left > first.target.box.left)
        assertTrue(selected.target.box.top > first.target.box.top)
    }

    @Test
    fun resetMovesSelectedTargetToLost() {
        val controller = SelectedTargetController()
        controller.selectManualTarget(NormalizedRect.fromCenter(0.5f, 0.5f, 0.28f, 0.28f))

        val state = controller.resetTarget(TargetLossReason.RESET)

        assertTrue(state is SelectedTargetState.Lost)
        val lost = state as SelectedTargetState.Lost
        assertEquals(TargetLossReason.RESET, lost.reason)
        assertTrue(lost.previousTarget != null)
    }

    @Test
    fun modeChangeKeepsNoneWhenNothingWasSelected() {
        val controller = SelectedTargetController()

        val state = controller.resetTarget(TargetLossReason.MODE_CHANGED)

        assertEquals(SelectedTargetState.None, state)
    }

    @Test
    fun coordinateConversionStaysInsideAnalysisSpace() {
        val selection = PreviewTargetMapper.manualSelectionForTap(
            tapX = 180f,
            tapY = 760f,
            viewWidth = 360f,
            viewHeight = 800f
        )

        assertTrue(selection.left in 0f..1f)
        assertTrue(selection.top in 0f..1f)
        assertTrue(selection.right in 0f..1f)
        assertTrue(selection.bottom in 0f..1f)

        val viewRect = PreviewTargetMapper.viewRectFor(selection, 360f, 800f)
        val analysisSquare = PreviewTargetMapper.analysisSquare(360f, 800f)

        assertTrue(viewRect.left >= analysisSquare.left)
        assertTrue(viewRect.top >= analysisSquare.top)
        assertTrue(viewRect.right <= analysisSquare.right)
        assertTrue(viewRect.bottom <= analysisSquare.bottom)
    }

    @Test
    fun selectedCropMapsInsideCenteredSquareAnalysisRegion() {
        val selection = NormalizedRect.fromCenter(0.5f, 0.5f, 0.28f, 0.28f)

        val pixelRect = SelectedTargetCropper.pixelRectFor(selection, imageWidth = 720, imageHeight = 1280)
        val analysisSquare = SelectedTargetCropper.analysisSquareRect(720, 1280)

        assertTrue(pixelRect.left >= analysisSquare.left)
        assertTrue(pixelRect.top >= analysisSquare.top)
        assertTrue(pixelRect.right <= analysisSquare.right)
        assertTrue(pixelRect.bottom <= analysisSquare.bottom)
    }

    @Test
    fun selectedCropClampsSafelyNearEdges() {
        val topLeft = NormalizedRect.fromCenter(0f, 0f, 0.28f, 0.28f)
        val bottomRight = NormalizedRect.fromCenter(1f, 1f, 0.28f, 0.28f)

        val topLeftRect = SelectedTargetCropper.pixelRectFor(topLeft, imageWidth = 720, imageHeight = 1280)
        val bottomRightRect = SelectedTargetCropper.pixelRectFor(bottomRight, imageWidth = 720, imageHeight = 1280)

        assertEquals(0, topLeftRect.left)
        assertEquals(280, topLeftRect.top)
        assertTrue(topLeftRect.width() > 0)
        assertTrue(topLeftRect.height() > 0)

        assertEquals(720, bottomRightRect.right)
        assertEquals(1000, bottomRightRect.bottom)
        assertTrue(bottomRightRect.left > topLeftRect.left)
        assertTrue(bottomRightRect.top > topLeftRect.top)
    }
}
