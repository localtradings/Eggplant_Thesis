package com.example.eggplantdetector

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.MotionEvent
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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var classifier: TFLiteImageClassifier
    private val selectedTargetController = SelectedTargetController()
    private val plantDetector: PlantDetector = PlaceholderPlantDetector()
    private val plantTracker: PlantTracker = ManualLockPlantTracker()

    private var captureMode = CaptureMode.PHOTO
    private var latestPreviewBitmap: Bitmap? = null
    private var latestFrameAssessment: FrameAssessment? = null
    private var latestCameraDebugSnapshot: DiagnosisDebugSnapshot? = null
    private var latestBundledDebugSnapshot: DiagnosisDebugSnapshot? = null
    private var displayedDebugSnapshot: DiagnosisDebugSnapshot? = null
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
        binding.debugSampleButton.isVisible = BuildConfig.DEBUG
        binding.debugSampleButton.setOnClickListener { runBundledDebugSampleDiagnosis() }
        if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
            binding.retakeButton.setOnClickListener {
                resetPhotoCapture(clearState = false)
                selectedTargetController.resetTarget(TargetLossReason.RESET)
                renderTargetState(selectedTargetController.state)
            }
            binding.retakeButton.text = getString(R.string.reset_target)
            binding.targetOverlayView.setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_UP) {
                    handlePreviewTap(event.x, event.y)
                }
                true
            }
            renderTargetState(selectedTargetController.state)
        } else {
            binding.retakeButton.setOnClickListener { resetPhotoCapture(clearState = true) }
            renderState(DiagnosisState.NeedsRetake(DiagnosisReason.CAPTURE_PHOTO))
        }
    }

    private val modeCheckedListener =
        MaterialButtonToggleGroup.OnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@OnButtonCheckedListener
            captureMode = if (checkedId == R.id.liveModeButton) CaptureMode.LIVE else CaptureMode.PHOTO
            resetPhotoCapture(clearState = captureMode == CaptureMode.PHOTO)
            if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
                selectedTargetController.resetTarget(TargetLossReason.MODE_CHANGED)
                renderTargetState(selectedTargetController.state)
                return@OnButtonCheckedListener
            }
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
            try {
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
            } catch (error: Exception) {
                Log.e("EggplantTargeting", "Camera start failed", error)
                if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
                    selectedTargetController.resetTarget(TargetLossReason.CAMERA_INTERRUPTED)
                    renderTargetState(selectedTargetController.state)
                } else {
                    Toast.makeText(this, "Camera could not start.", Toast.LENGTH_LONG).show()
                }
            }
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
            runOnUiThread {
                if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
                    selectedTargetController.resetTarget(TargetLossReason.CAMERA_INTERRUPTED)
                    renderTargetState(selectedTargetController.state)
                } else {
                    renderState(DiagnosisState.NeedsRetake(DiagnosisReason.FRAME_SINGLE_LEAF))
                }
            }
            return
        }

        latestPreviewBitmap = bitmap
        if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
            handleManualTargetingFrame(bitmap)
            return
        }
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
        if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
            val selectedTarget = selectedTargetOrNull()
            val bitmap = latestPreviewBitmap
            if (selectedTarget == null || bitmap == null) {
                renderTargetState(selectedTargetController.state)
                return
            }

            val frozenBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
            isFrozen = true
            binding.capturedFrameView.setImageBitmap(frozenBitmap)
            binding.capturedFrameView.isVisible = true
            binding.captureButton.isVisible = false
            binding.retakeButton.isVisible = true
            binding.actionRow.isVisible = true
            binding.modeHelper.text = getString(R.string.analyzing_selected_target)

            cameraExecutor.execute {
                val selectedCrop = cropSelectedTarget(frozenBitmap, selectedTarget.box)
                val assessment = assessFrame(selectedCrop)
                latestFrameAssessment = assessment
                val result = classifier.classify(selectedCrop)
                // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
                val state = DiagnosisRules.photoDiagnosis(assessment, result)
                publishCameraDebugSnapshot(
                    buildDebugSnapshot(
                    sourceType = DebugDiagnosisSource.SELECTED_TARGET,
                    sourceLabel = "Source: Camera Selected Crop",
                    fileLabel = "Selected crop from active camera target",
                    sourceBitmap = selectedCrop,
                    assessment = assessment,
                    result = result,
                    state = state,
                    mode = CaptureMode.PHOTO
                    )
                )
                logDiagnosis(state, assessment, CaptureMode.PHOTO)
                runOnUiThread { renderState(state) }
            }
            return
        }
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
        if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
            when (selectedTargetController.state) {
                SelectedTargetState.None,
                is SelectedTargetState.Lost -> {
                    binding.captureButton.isVisible = false
                    binding.retakeButton.isVisible = false
                    binding.actionRow.isVisible = false
                }

                is SelectedTargetState.Selected -> {
                    binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO
                    binding.retakeButton.isVisible = true
                    binding.actionRow.isVisible = true
                }
            }
            if (clearState) {
                renderTargetState(selectedTargetController.state)
            }
            return
        }
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
        if (TargetSelectionContract.isPhase1ManualTargetingEnabled) {
            if (selectedTargetOrNull() == null) {
                renderTargetState(selectedTargetController.state)
                return
            }
            binding.modeHelper.text = when (captureMode) {
                CaptureMode.LIVE -> getString(R.string.analyzing_selected_target)
                CaptureMode.PHOTO -> if (isFrozen) {
                    getString(R.string.selected_target_photo_ready)
                } else {
                    getString(R.string.selected_target_photo_prompt)
                }
            }
            binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO && !isFrozen
            binding.retakeButton.isVisible = true
            binding.actionRow.isVisible = true
        } else {
            binding.modeHelper.text = when {
                captureMode == CaptureMode.LIVE -> getString(R.string.live_mode_helper)
                isFrozen -> getString(R.string.photo_frozen_helper)
                else -> getString(R.string.photo_mode_helper)
            }
            binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO && !isFrozen
            binding.retakeButton.isVisible = captureMode == CaptureMode.PHOTO && isFrozen
        }

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

        renderDebugSnapshot(displayedDebugSnapshot)
    }

    private fun handlePreviewTap(x: Float, y: Float) {
        if (!TargetSelectionContract.isPhase1ManualTargetingEnabled) return
        if (binding.targetOverlayView.width == 0 || binding.targetOverlayView.height == 0) return
        resetPhotoCapture(clearState = false)
        val selectedBox = PreviewTargetMapper.manualSelectionForTap(
            tapX = x,
            tapY = y,
            viewWidth = binding.targetOverlayView.width.toFloat(),
            viewHeight = binding.targetOverlayView.height.toFloat()
        )
        selectedTargetController.selectManualTarget(selectedBox)
        renderTargetState(selectedTargetController.state)
    }

    private fun handleManualTargetingFrame(bitmap: Bitmap) {
        // Future eggplant detector hook: replace PlaceholderPlantDetector with a real detector that returns plant boxes.
        val candidatePlants = plantDetector.detectCandidates(bitmap)
        // Future tracking hook: replace ManualLockPlantTracker with a real tracker that updates the selected target.
        val updatedState = plantTracker.updateSelectedTarget(selectedTargetController.state, candidatePlants)
        if (updatedState != selectedTargetController.state) {
            selectedTargetController.applyTrackedState(updatedState)
            runOnUiThread { renderTargetState(selectedTargetController.state) }
        }

        when (val targetState = selectedTargetController.state) {
            SelectedTargetState.None,
            is SelectedTargetState.Lost -> return

            is SelectedTargetState.Selected -> {
                when (captureMode) {
                    CaptureMode.LIVE -> {
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastAnalysisTimestampMs < ModelContract.liveInferenceIntervalMs) return
                        lastAnalysisTimestampMs = now

                        // Selected-target crop happens here so the existing classifier and diagnosis rules receive only the manual target region.
                        val selectedCrop = cropSelectedTarget(bitmap, targetState.target.box)
                        val assessment = assessFrame(selectedCrop)
                        latestFrameAssessment = assessment
                        val result = classifier.classify(selectedCrop)
                        // Future treatment hook: attach post-diagnosis treatment guidance after the selected-target diagnosis result is finalized.
                        val state = DiagnosisRules.liveDiagnosis(assessment, result)
                        publishCameraDebugSnapshot(
                            buildDebugSnapshot(
                            sourceType = DebugDiagnosisSource.SELECTED_TARGET,
                            sourceLabel = "Source: Camera Selected Crop",
                            fileLabel = "Selected crop from active camera target",
                            sourceBitmap = selectedCrop,
                            assessment = assessment,
                            result = result,
                            state = state,
                            mode = CaptureMode.LIVE
                            )
                        )
                        logDiagnosis(state, assessment, CaptureMode.LIVE)
                        runOnUiThread { renderState(state) }
                    }

                    CaptureMode.PHOTO -> {
                        return
                    }
                }
            }
        }
    }

    private fun renderTargetState(state: SelectedTargetState) {
        binding.targetOverlayView.targetState = state
        binding.resultTitle.text = getString(R.string.target_selection_title)
        binding.resultDetails.text = getString(R.string.target_selection_detail)
        if (state !is SelectedTargetState.Selected && displayedDebugSnapshot?.sourceType == DebugDiagnosisSource.SELECTED_TARGET) {
            latestCameraDebugSnapshot = null
            displayedDebugSnapshot = latestBundledDebugSnapshot
        }

        when (state) {
            SelectedTargetState.None -> {
                binding.modeHelper.text = getString(R.string.target_none_title)
                binding.resultLabel.text = getString(R.string.target_none_title)
                binding.resultScore.text = getString(R.string.target_none_body)
                binding.captureButton.isVisible = false
                binding.retakeButton.isVisible = false
                binding.actionRow.isVisible = false
            }

            is SelectedTargetState.Selected -> {
                val helperText = if (captureMode == CaptureMode.LIVE) {
                    getString(R.string.analyzing_selected_target)
                } else {
                    getString(R.string.selected_target_photo_prompt)
                }
                binding.modeHelper.text = helperText
                binding.resultLabel.text = getString(R.string.target_selected_title)
                binding.resultScore.text = helperText
                binding.captureButton.isVisible = captureMode == CaptureMode.PHOTO && !isFrozen
                binding.retakeButton.isVisible = true
                binding.actionRow.isVisible = true
            }

            is SelectedTargetState.Lost -> {
                binding.modeHelper.text = getString(R.string.target_lost_title)
                binding.resultLabel.text = getString(R.string.target_lost_title)
                binding.resultScore.text = getString(R.string.target_lost_body)
                binding.captureButton.isVisible = false
                binding.retakeButton.isVisible = false
                binding.actionRow.isVisible = false
            }
        }

        renderDebugSnapshot(displayedDebugSnapshot)
    }

    private fun selectedTargetOrNull(): SelectedPlantTarget? {
        return (selectedTargetController.state as? SelectedTargetState.Selected)?.target
    }

    private fun cropSelectedTarget(bitmap: Bitmap, box: NormalizedRect): Bitmap {
        return SelectedTargetCropper.cropBitmap(bitmap, box)
    }

    private fun runBundledDebugSampleDiagnosis() {
        if (!BuildConfig.DEBUG) return
        binding.debugSampleButton.isEnabled = false
        cameraExecutor.execute {
            val sample = loadBundledDebugSampleBitmap()
            val snapshot = if (sample == null) {
                DiagnosisDebugSnapshot(
                    sourceType = DebugDiagnosisSource.BUNDLED_SAMPLE,
                    sourceLabel = "Source: Bundled Sample",
                    fileLabel = "No bundled debug sample found.",
                    previewBitmap = null,
                    details = "No bundled debug sample found."
                )
            } else {
                val assessment = assessFrame(sample.bitmap)
                val result = classifier.classify(sample.bitmap)
                val state = DiagnosisRules.photoDiagnosis(assessment, result)
                buildDebugSnapshot(
                    sourceType = DebugDiagnosisSource.BUNDLED_SAMPLE,
                    sourceLabel = "Source: Bundled Sample",
                    fileLabel = sample.filename,
                    sourceBitmap = sample.bitmap,
                    assessment = assessment,
                    result = result,
                    state = state,
                    mode = CaptureMode.PHOTO
                )
            }

            publishBundledDebugSnapshot(snapshot)
            runOnUiThread {
                binding.debugSampleButton.isEnabled = true
                renderDebugSnapshot(displayedDebugSnapshot)
            }
        }
    }

    private fun loadBundledDebugSampleBitmap(): BundledDebugSample? {
        val debugSampleNames = assets.list("debug_samples")
            ?.filter { it.endsWith(".jpg", ignoreCase = true) || it.endsWith(".jpeg", ignoreCase = true) || it.endsWith(".png", ignoreCase = true) }
            ?.sorted()
            .orEmpty()

        val assetName = debugSampleNames.firstOrNull() ?: return null
        val bitmap = assets.open("debug_samples/$assetName").use(BitmapFactory::decodeStream) ?: return null
        return BundledDebugSample(filename = assetName, bitmap = bitmap)
    }

    private fun buildDebugSnapshot(
        sourceType: DebugDiagnosisSource,
        sourceLabel: String,
        fileLabel: String,
        sourceBitmap: Bitmap,
        assessment: FrameAssessment,
        result: TFLiteImageClassifier.ClassificationResult?,
        state: DiagnosisState,
        mode: CaptureMode
    ): DiagnosisDebugSnapshot {
        val previewBitmap = classifier.prepareDebugBitmap(sourceBitmap)
        val details = listOf(
            "File: $fileLabel",
            "Source image: ${sourceBitmap.width}x${sourceBitmap.height}",
            "Classifier input: ${previewBitmap.width}x${previewBitmap.height}",
            DiagnosisDebugTrace.rawTopResults(result),
            DiagnosisDebugTrace.assessmentSummary(assessment),
            DiagnosisDebugTrace.decisionPath(mode, assessment, result, state)
        ).joinToString(separator = "\n\n")
        return DiagnosisDebugSnapshot(sourceType, sourceLabel, previewBitmap, details)
    }

    private fun renderDebugSnapshot(snapshot: DiagnosisDebugSnapshot?) {
        val shouldShowDebug = BuildConfig.DEBUG && snapshot != null
        binding.debugSection.isVisible = shouldShowDebug
        if (!shouldShowDebug) {
            binding.debugCropPreview.setImageDrawable(null)
            return
        }

        binding.debugSource.text = snapshot!!.sourceLabel
        binding.debugDetails.text = snapshot.details
        if (snapshot.previewBitmap != null) {
            binding.debugCropPreview.isVisible = true
            binding.debugCropPreview.setImageBitmap(snapshot.previewBitmap)
        } else {
            binding.debugCropPreview.isVisible = false
            binding.debugCropPreview.setImageDrawable(null)
        }
    }

    private fun publishCameraDebugSnapshot(snapshot: DiagnosisDebugSnapshot) {
        latestCameraDebugSnapshot = snapshot
        if (displayedDebugSnapshot?.sourceType != DebugDiagnosisSource.BUNDLED_SAMPLE) {
            displayedDebugSnapshot = snapshot
        }
    }

    private fun publishBundledDebugSnapshot(snapshot: DiagnosisDebugSnapshot) {
        latestBundledDebugSnapshot = snapshot
        displayedDebugSnapshot = snapshot
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

private enum class DebugDiagnosisSource {
    SELECTED_TARGET,
    BUNDLED_SAMPLE
}

private data class DiagnosisDebugSnapshot(
    val sourceType: DebugDiagnosisSource,
    val sourceLabel: String,
    val previewBitmap: Bitmap?,
    val details: String
)

private data class BundledDebugSample(
    val filename: String,
    val bitmap: Bitmap
)
