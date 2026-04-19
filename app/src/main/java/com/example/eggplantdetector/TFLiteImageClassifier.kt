package com.example.eggplantdetector

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.Closeable
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

class TFLiteImageClassifier(context: Context) : Closeable {

    data class Prediction(val label: String, val confidence: Float)
    data class ClassificationResult(
        val label: String,
        val confidence: Float,
        val topResults: List<Prediction>
    )

    private val interpreter: Interpreter
    private val labels: List<String>
    private val inputHeight: Int
    private val inputWidth: Int
    private val inputChannels: Int
    private val inputType: DataType
    private val outputType: DataType
    private val inputScale: Float
    private val inputZeroPoint: Int
    private val outputScale: Float
    private val outputZeroPoint: Int

    init {
        interpreter = Interpreter(
            loadModelFile(context, "model.tflite"),
            Interpreter.Options().apply { setNumThreads(4) }
        )
        labels = context.assets.open("labels.txt")
            .bufferedReader()
            .readLines()
            .filter { it.isNotBlank() }

        val inputTensor = interpreter.getInputTensor(0)
        val outputTensor = interpreter.getOutputTensor(0)
        val inputShape = inputTensor.shape()
        inputHeight = inputShape[1]
        inputWidth = inputShape[2]
        inputChannels = inputShape[3]
        inputType = inputTensor.dataType()
        outputType = outputTensor.dataType()
        val inputQuantization = inputTensor.quantizationParams()
        inputScale = inputQuantization.scale
        inputZeroPoint = inputQuantization.zeroPoint
        val outputQuantization = outputTensor.quantizationParams()
        outputScale = outputQuantization.scale
        outputZeroPoint = outputQuantization.zeroPoint

        Log.i(
            "TFLiteImageClassifier",
            "Model contract: input=$inputType ${inputWidth}x$inputHeight x$inputChannels, output=$outputType, preprocessing=${ModelContract.preprocessingSummary}"
        )
    }

    fun classify(bitmap: Bitmap): ClassificationResult? {
        val preparedBitmap = prepareDebugBitmap(bitmap)
        val inputBuffer = bitmapToBuffer(preparedBitmap)

        val output = when (outputType) {
            DataType.FLOAT32 -> Array(1) { FloatArray(labels.size) }
            DataType.UINT8 -> Array(1) { ByteArray(labels.size) }
            DataType.INT8 -> Array(1) { ByteArray(labels.size) }
            else -> return null
        }

        interpreter.run(inputBuffer, output)
        val predictions = when (output) {
            is Array<*> -> {
                when (val first = output.firstOrNull()) {
                    is FloatArray -> first.mapIndexed { index, score ->
                        Prediction(labels.getOrElse(index) { "class_$index" }, score)
                    }

                    is ByteArray -> first.mapIndexed { index, score ->
                        Prediction(labels.getOrElse(index) { "class_$index" }, decodeByteScore(score))
                    }

                    else -> emptyList()
                }
            }

            else -> emptyList()
        }

        val topResults = predictions
            .sortedByDescending { it.confidence }
            .take(3)

        return topResults.firstOrNull()?.let { best ->
            ClassificationResult(
                label = best.label,
                confidence = best.confidence,
                topResults = topResults
            )
        }
    }

    fun prepareDebugBitmap(bitmap: Bitmap): Bitmap {
        return bitmap.centerCrop().scaleToModelInput(inputWidth, inputHeight)
    }

    private fun bitmapToBuffer(bitmap: Bitmap): ByteBuffer {
        val bytesPerChannel = if (inputType == DataType.FLOAT32) 4 else 1
        val inputBuffer = ByteBuffer.allocateDirect(
            inputWidth * inputHeight * inputChannels * bytesPerChannel
        ).order(ByteOrder.nativeOrder())

        val intValues = IntArray(inputWidth * inputHeight)
        bitmap.getPixels(intValues, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)

        for (pixel in intValues) {
            val red = (pixel shr 16 and 0xFF)
            val green = (pixel shr 8 and 0xFF)
            val blue = (pixel and 0xFF)

            if (inputType == DataType.FLOAT32) {
                inputBuffer.putFloat(red / 255f)
                inputBuffer.putFloat(green / 255f)
                inputBuffer.putFloat(blue / 255f)
            } else {
                inputBuffer.put(quantizeColor(red))
                inputBuffer.put(quantizeColor(green))
                inputBuffer.put(quantizeColor(blue))
            }
        }

        inputBuffer.rewind()
        return inputBuffer
    }

    private fun quantizeColor(channelValue: Int): Byte {
        val normalized = channelValue / 255f
        if (inputScale == 0f) return channelValue.toByte()
        val quantized = (normalized / inputScale + inputZeroPoint).toInt()
        return when (inputType) {
            DataType.INT8 -> quantized.coerceIn(-128, 127).toByte()
            else -> quantized.coerceIn(0, 255).toByte()
        }
    }

    private fun decodeByteScore(score: Byte): Float {
        val rawValue = when (outputType) {
            DataType.INT8 -> score.toInt()
            else -> score.toInt() and 0xFF
        }
        if (outputScale != 0f) {
            return ((rawValue - outputZeroPoint) * outputScale).coerceIn(0f, 1f)
        }
        return (rawValue / 255f).coerceIn(0f, 1f)
    }

    private fun Bitmap.centerCrop(): Bitmap {
        if (width == height) return this
        val size = minOf(width, height)
        val xOffset = (width - size) / 2
        val yOffset = (height - size) / 2
        return Bitmap.createBitmap(this, xOffset, yOffset, size, size)
    }

    private fun Bitmap.scaleToModelInput(targetWidth: Int, targetHeight: Int): Bitmap {
        if (width == targetWidth && height == targetHeight) return this
        return Bitmap.createScaledBitmap(this, targetWidth, targetHeight, true)
    }

    override fun close() {
        interpreter.close()
    }

    private fun loadModelFile(context: Context, assetName: String): ByteBuffer {
        val fileDescriptor = context.assets.openFd(assetName)
        FileInputStream(fileDescriptor.fileDescriptor).channel.use { fileChannel ->
            return fileChannel.map(
                FileChannel.MapMode.READ_ONLY,
                fileDescriptor.startOffset,
                fileDescriptor.declaredLength
            )
        }
    }
}
