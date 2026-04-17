package com.example.eggplantdetector

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import com.example.eggplantdetector.databinding.ActivityMainBinding
import com.google.android.material.button.MaterialButtonToggleGroup
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var classifier: TFLiteImageClassifier

    private var captureMode = CaptureMode.PHOTO
    private var latestPreviewBitmap: Bitmap? = null
    private var latestFrameAssessment: FrameAssessment? = null
    private var lastAnalysisTimestampMs = 0L
    private var isFrozen = false

    private val cameraPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                startCamera()
            } else {
                Toast.makeText(this, "Camera permission is required.", Toast.LENGTH_LONG).show()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        cameraExecutor = Executors.newSingleThreadExecutor()
        classifier = TFLiteImageClassifier(this)
        configureUi()

        if (hasCameraPermission()) {
            startCamera()
        } else {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        classifier.close()
        cameraExecutor.shutdown()
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun configureUi() {
        binding.modeToggleGroup.check(R.id.photoModeButton)
        binding.modeToggleGroup.addOnButtonCheckedListener(modeCheckedListener)
        binding.captureButton.setOnClickListener { capturePhotoDiagnosis() }
        binding.retakeButton.setOnClickListener { resetPhotoCapture(clearState = true) }
        renderState(DiagnosisState.NeedsRetake(DiagnosisReason.CAPTURE_PHOTO))
    }

    private val modeCheckedListener =
        MaterialButtonToggleGroup.OnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@OnButtonCheckedListener
            captureMode = if (checkedId == R.id.liveModeButton) CaptureMode.LIVE else CaptureMode.PHOTO
            resetPhotoCapture(clearState = captureMode == CaptureMode.PHOTO)
            val defaultState = if (captureMode == CaptureMode.LIVE) {
                DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF)
            } else {
                DiagnosisState.NeedsRetake(DiagnosisReason.CAPTURE_PHOTO)
            }
            renderState(defaultState)
        }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .build()
                .also { it.surfaceProvider = binding.previewView.surfaceProvider }

            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor) { imageProxy ->
                        analyzeImage(imageProxy)
                    }
                }

            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageAnalysis
            )
        }, ContextCompat.getMainExecutor(this))
    }

    private fun analyzeImage(imageProxy: ImageProxy) {
        if (isFrozen) {
            imageProxy.close()
            return
        }

        val bitmap = imageProxy.toBitmap()
        imageProxy.close()
        if (bitmap == null) {
            runOnUiThread { renderState(DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF)) }
            return
        }

        latestPreviewBitmap = bitmap
        val assessment = assessFrame(bitmap)
        latestFrameAssessment = assessment

        when (captureMode) {
            CaptureMode.LIVE -> {
                val now = SystemClock.elapsedRealtime()
                if (now - lastAnalysisTimestampMs < ModelContract.liveInferenceIntervalMs) return
                lastAnalysisTimestampMs = now
                val state = DiagnosisRules.liveDiagnosis(assessment, classifier.classify(bitmap))
                logDiagnosis(state, assessment, CaptureMode.LIVE)
                runOnUiThread { renderState(state) }
            }

            CaptureMode.PHOTO -> {
                val state = DiagnosisRules.photoAssist(assessment)
                runOnUiThread { renderState(state) }
            }
        }
    }

    private fun capturePhotoDiagnosis() {
        if (captureMode != CaptureMode.PHOTO) return
        val bitmap = latestPreviewBitmap
        val assessment = latestFrameAssessment
        if (bitmap == null || assessment == null) {
            renderState(DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF))
            return
        }

        val frozenBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
        isFrozen = true
        binding.capturedFrameView.setImageBitmap(frozenBitmap)
        binding.capturedFrameView.isVisible = true
        binding.captureButton.isVisible = false
        binding.retakeButton.isVisible = true
        binding.modeHelper.text = getString(R.string.analyzing_photo)

        cameraExecutor.execute {
            val state = DiagnosisRules.photoDiagnosis(assessment, classifier.classify(frozenBitmap))
            logDiagnosis(state, assessment, CaptureMode.PHOTO)
            runOnUiThread { renderState(state) }
        }
    }

    private fun resetPhotoCapture(clearState: Boolean) {
        isFrozen = false
        binding.capturedFrameView.setImageDrawable(null)
        binding.capturedFrameView.isVisible = false
        binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO
        binding.retakeButton.isVisible = false
        if (clearState && captureMode == CaptureMode.PHOTO) {
            renderState(DiagnosisState.NeedsRetake(DiagnosisReason.CAPTURE_PHOTO))
        }
    }

    private fun assessFrame(bitmap: Bitmap): FrameAssessment {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        var lumaAccumulator = 0f
        var likelyLeafPixels = 0
        var centerLeafPixels = 0
        var centerPixels = 0
        val centerStartX = bitmap.width / 4
        val centerEndX = bitmap.width - centerStartX
        val centerStartY = bitmap.height / 4
        val centerEndY = bitmap.height - centerStartY
        for ((index, pixel) in pixels.withIndex()) {
            val red = (pixel shr 16 and 0xFF) / 255f
            val green = (pixel shr 8 and 0xFF) / 255f
            val blue = (pixel and 0xFF) / 255f
            lumaAccumulator += (0.2126f * red) + (0.7152f * green) + (0.0722f * blue)

            if (isLikelyLeafPixel(red, green, blue)) {
                likelyLeafPixels++
                val x = index % bitmap.width
                val y = index / bitmap.width
                if (x in centerStartX until centerEndX && y in centerStartY until centerEndY) {
                    centerLeafPixels++
                }
            }

            val x = index % bitmap.width
            val y = index / bitmap.width
            if (x in centerStartX until centerEndX && y in centerStartY until centerEndY) {
                centerPixels++
            }
        }
        return FrameAssessment(
            meanBrightness = lumaAccumulator / pixels.size,
            likelyLeafRatio = likelyLeafPixels.toFloat() / pixels.size,
            centerLeafRatio = if (centerPixels == 0) 0f else centerLeafPixels.toFloat() / centerPixels
        )
    }

    private fun isLikelyLeafPixel(red: Float, green: Float, blue: Float): Boolean {
        val maxChannel = maxOf(red, green, blue)
        val minChannel = minOf(red, green, blue)
        val chroma = maxChannel - minChannel
        val saturation = if (maxChannel == 0f) 0f else chroma / maxChannel
        val value = maxChannel
        if (value < 0.18f || saturation < 0.2f) {
            return false
        }

        val hue = when {
            chroma == 0f -> 0f
            maxChannel == red -> 60f * (((green - blue) / chroma) % 6f)
            maxChannel == green -> 60f * (((blue - red) / chroma) + 2f)
            else -> 60f * (((red - green) / chroma) + 4f)
        }
        val normalizedHue = if (hue < 0f) hue + 360f else hue
        val greenEnough = green > red * 1.03f && green > blue * 1.08f
        val inLeafHueBand = normalizedHue in 55f..165f
        return greenEnough && inLeafHueBand
    }

    private fun renderState(state: DiagnosisState) {
        binding.modeHelper.text = when {
            captureMode == CaptureMode.LIVE -> getString(R.string.live_mode_helper)
            isFrozen -> getString(R.string.photo_frozen_helper)
            else -> getString(R.string.photo_mode_helper)
        }
        binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO && !isFrozen
        binding.retakeButton.isVisible = captureMode == CaptureMode.PHOTO && isFrozen

        when (state) {
            is DiagnosisState.Confirmed -> {
                binding.resultTitle.text = getString(
                    if (captureMode == CaptureMode.LIVE) {
                        R.string.live_mode_title
                    } else {
                        R.string.photo_mode_title
                    }
                )
                binding.resultLabel.text = state.label.replace('_', ' ')
                binding.resultScore.text = getString(R.string.confidence_template, state.confidence * 100f)
                binding.resultDetails.text = state.topResults.joinToString(separator = "\n") {
                    "${it.label.replace('_', ' ')}: ${"%.1f".format(it.confidence * 100f)}%"
                }
            }

            is DiagnosisState.Uncertain -> {
                binding.resultTitle.text = getString(R.string.uncertain_title)
                binding.resultLabel.text = getReasonTitle(state.reason)
                binding.resultScore.text = getString(R.string.uncertain_subtitle)
                binding.resultDetails.text = state.topResults.joinToString(separator = "\n") {
                    "${it.label.replace('_', ' ')}: ${"%.1f".format(it.confidence * 100f)}%"
                }
            }

            is DiagnosisState.NeedsRetake -> {
                binding.resultTitle.text = getString(R.string.guidance_title)
                binding.resultLabel.text = getReasonTitle(state.reason)
                binding.resultScore.text = getReasonBody(state.reason)
                binding.resultDetails.text = getString(R.string.contract_summary)
            }
        }
    }

    private fun getReasonTitle(reason: DiagnosisReason): String {
        return when (reason) {
            DiagnosisReason.CAPTURE_PHOTO -> getString(R.string.capture_photo_title)
            DiagnosisReason.NO_LEAF_DETECTED -> getString(R.string.no_leaf_title)
            DiagnosisReason.FRAME_SINGLE_LEAF -> getString(R.string.frame_single_leaf_title)
            DiagnosisReason.INCREASE_LIGHT -> getString(R.string.increase_light_title)
            DiagnosisReason.REDUCE_GLARE -> getString(R.string.reduce_glare_title)
            DiagnosisReason.LOW_CONFIDENCE -> getString(R.string.low_confidence_title)
            DiagnosisReason.AMBIGUOUS -> getString(R.string.ambiguous_title)
        }
    }

    private fun getReasonBody(reason: DiagnosisReason): String {
        return when (reason) {
            DiagnosisReason.CAPTURE_PHOTO -> getString(R.string.capture_photo_body)
            DiagnosisReason.NO_LEAF_DETECTED -> getString(R.string.no_leaf_body)
            DiagnosisReason.FRAME_SINGLE_LEAF -> getString(R.string.frame_single_leaf_body)
            DiagnosisReason.INCREASE_LIGHT -> getString(R.string.increase_light_body)
            DiagnosisReason.REDUCE_GLARE -> getString(R.string.reduce_glare_body)
            DiagnosisReason.LOW_CONFIDENCE -> getString(R.string.low_confidence_body)
            DiagnosisReason.AMBIGUOUS -> getString(R.string.ambiguous_body)
        }
    }

    private fun logDiagnosis(state: DiagnosisState, assessment: FrameAssessment, mode: CaptureMode) {
        Log.d(
            "EggplantDiagnosis",
            "mode=$mode brightness=${"%.3f".format(assessment.meanBrightness)} leafRatio=${"%.3f".format(assessment.likelyLeafRatio)} centerLeafRatio=${"%.3f".format(assessment.centerLeafRatio)} state=$state"
        )
    }

    private fun ImageProxy.toBitmap(): Bitmap? {
        val plane = planes.firstOrNull() ?: return null
        val buffer = plane.buffer.duplicate()
        buffer.rewind()
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val rowBytes = ByteArray(rowStride)
        val pixels = IntArray(width * height)

        for (row in 0 until height) {
            buffer.position(row * rowStride)
            buffer.get(rowBytes, 0, rowStride)
            for (column in 0 until width) {
                val offset = column * pixelStride
                val red = rowBytes[offset].toInt() and 0xFF
                val green = rowBytes[offset + 1].toInt() and 0xFF
                val blue = rowBytes[offset + 2].toInt() and 0xFF
                pixels[row * width + column] = -0x1000000 or
                    (red shl 16) or
                    (green shl 8) or
                    blue
            }
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap.rotate(imageInfo.rotationDegrees)
    }

    private fun Bitmap.rotate(rotationDegrees: Int): Bitmap {
        if (rotationDegrees == 0) return this
        val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }
}
