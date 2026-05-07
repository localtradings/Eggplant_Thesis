package com.example.eggplantdetector

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat

class TargetOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val selectedStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        color = ContextCompat.getColor(context, R.color.seed)
    }

    private val selectedFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(36, 77, 170, 87)
    }

    private val lostStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        color = ContextCompat.getColor(context, R.color.secondaryText)
        pathEffect = DashPathEffect(floatArrayOf(18f, 12f), 0f)
    }

    private val lostFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(20, 215, 210, 199)
    }

    var targetState: SelectedTargetState = SelectedTargetState.None
        set(value) {
            field = value
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val targetInfo: Pair<SelectedPlantTarget, Boolean> = when (val state = targetState) {
            is SelectedTargetState.Selected -> state.target to false
            is SelectedTargetState.Lost -> state.previousTarget?.let { it to true }
            SelectedTargetState.None -> null
        } ?: return
        val (target, isLost) = targetInfo

        val rect = PreviewTargetMapper.viewRectFor(
            box = target.box,
            viewWidth = width.toFloat(),
            viewHeight = height.toFloat()
        )
        val cornerRadius = 22f
        val fillPaint = if (isLost) lostFillPaint else selectedFillPaint
        val strokePaint = if (isLost) lostStrokePaint else selectedStrokePaint
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, fillPaint)
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, strokePaint)
    }
}
