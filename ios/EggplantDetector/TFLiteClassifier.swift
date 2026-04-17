import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import TensorFlowLite
import UIKit

struct PredictionScore: Equatable {
    let label: String
    let confidence: Float
}

struct ClassificationResult {
    let label: String
    let confidence: Float
    let topResults: [PredictionScore]
}

struct PreparedFrame {
    let inputData: Data
    let assessment: FrameAssessment
    let displayImage: UIImage
}

final class TFLiteClassifier {
    private let interpreter: Interpreter
    private let labels: [String]
    private let inputWidth: Int
    private let inputHeight: Int
    private let inputChannels: Int
    private let ciContext = CIContext()

    init() throws {
        guard let modelPath = Bundle.main.path(forResource: "model", ofType: "tflite") else {
            throw ClassifierError.missingModel
        }

        guard let labelsPath = Bundle.main.path(forResource: "labels", ofType: "txt") else {
            throw ClassifierError.missingLabels
        }

        labels = try String(contentsOfFile: labelsPath)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        interpreter = try Interpreter(modelPath: modelPath, options: Interpreter.Options())
        try interpreter.allocateTensors()

        let shape = try interpreter.input(at: 0).shape.dimensions
        inputHeight = shape[1]
        inputWidth = shape[2]
        inputChannels = shape[3]

        NSLog(
            "Model contract: input=%dx%d x%d preprocessing=%@",
            inputWidth,
            inputHeight,
            inputChannels,
            ModelContract.preprocessingSummary
        )
    }

    func prepareFrame(pixelBuffer: CVPixelBuffer, crop: NormalizedRect? = nil) throws -> PreparedFrame {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let squareImage = sourceImage.centerCroppedToSquare()
        // Selected-target crop happens here so the existing preprocessing and diagnosis pipeline receive only the manual target region.
        let croppedImage = crop.map { squareImage.cropped(toNormalizedRect: $0) } ?? squareImage
        let preparedImage = croppedImage.resized(to: CGSize(width: inputWidth, height: inputHeight))

        var outputBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            inputWidth,
            inputHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer else {
            throw ClassifierError.pixelBufferCreationFailed
        }

        ciContext.render(preparedImage, to: outputBuffer)

        CVPixelBufferLockBaseAddress(outputBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else {
            throw ClassifierError.pixelBufferReadFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        var inputData = Data(capacity: inputWidth * inputHeight * inputChannels * MemoryLayout<Float32>.size)
        var lumaAccumulator: Float = 0
        var likelyLeafPixels = 0
        var centerLeafPixels = 0
        var centerPixels = 0
        let centerStartX = inputWidth / 4
        let centerEndX = inputWidth - centerStartX
        let centerStartY = inputHeight / 4
        let centerEndY = inputHeight - centerStartY

        for y in 0..<inputHeight {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in 0..<inputWidth {
                let pixel = row.advanced(by: x * 4)
                let blue = Float(pixel[0]) / 255.0
                let green = Float(pixel[1]) / 255.0
                let red = Float(pixel[2]) / 255.0

                inputData.append(float: red)
                inputData.append(float: green)
                inputData.append(float: blue)
                lumaAccumulator += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

                if isLikelyLeafPixel(red: red, green: green, blue: blue) {
                    likelyLeafPixels += 1
                    if x >= centerStartX && x < centerEndX && y >= centerStartY && y < centerEndY {
                        centerLeafPixels += 1
                    }
                }
                if x >= centerStartX && x < centerEndX && y >= centerStartY && y < centerEndY {
                    centerPixels += 1
                }
            }
        }

        guard let cgImage = ciContext.createCGImage(preparedImage, from: preparedImage.extent) else {
            throw ClassifierError.pixelBufferReadFailed
        }

        return PreparedFrame(
            inputData: inputData,
            assessment: FrameAssessment(
                meanBrightness: lumaAccumulator / Float(inputWidth * inputHeight),
                likelyLeafRatio: Float(likelyLeafPixels) / Float(inputWidth * inputHeight),
                centerLeafRatio: centerPixels == 0 ? 0 : Float(centerLeafPixels) / Float(centerPixels)
            ),
            displayImage: UIImage(cgImage: cgImage)
        )
    }

    func classify(preparedFrame: PreparedFrame) throws -> ClassificationResult {
        try interpreter.copy(preparedFrame.inputData, toInputAt: 0)
        try interpreter.invoke()

        let outputTensor = try interpreter.output(at: 0)
        let scores = outputTensor.data.toArray(type: Float32.self)

        let ranked = scores.enumerated()
            .map { index, score in
                PredictionScore(
                    label: labels[safe: index] ?? "class_\(index)",
                    confidence: score
                )
            }
            .sorted { $0.confidence > $1.confidence }

        let top = Array(ranked.prefix(3))
        let best = top.first ?? PredictionScore(label: "No result", confidence: 0)
        return ClassificationResult(label: best.label, confidence: best.confidence, topResults: top)
    }
}

private func isLikelyLeafPixel(red: Float, green: Float, blue: Float) -> Bool {
    let maxChannel = max(red, green, blue)
    let minChannel = min(red, green, blue)
    let chroma = maxChannel - minChannel
    let saturation: Float = maxChannel == 0 ? 0 : chroma / maxChannel
    let value = maxChannel

    if value < 0.18 || saturation < 0.2 {
        return false
    }

    let hue: Float
    if chroma == 0 {
        hue = 0
    } else if maxChannel == red {
        hue = 60 * (((green - blue) / chroma).truncatingRemainder(dividingBy: 6))
    } else if maxChannel == green {
        hue = 60 * (((blue - red) / chroma) + 2)
    } else {
        hue = 60 * (((red - green) / chroma) + 4)
    }

    let normalizedHue = hue < 0 ? hue + 360 : hue
    let greenEnough = green > red * 1.03 && green > blue * 1.08
    let inLeafHueBand = normalizedHue >= 55 && normalizedHue <= 165
    return greenEnough && inLeafHueBand
}

private enum ClassifierError: LocalizedError {
    case missingModel
    case missingLabels
    case pixelBufferCreationFailed
    case pixelBufferReadFailed

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "model.tflite was not found in the app bundle."
        case .missingLabels:
            return "labels.txt was not found in the app bundle."
        case .pixelBufferCreationFailed:
            return "The resized frame buffer could not be created."
        case .pixelBufferReadFailed:
            return "The frame buffer could not be read."
        }
    }
}

private extension Data {
    mutating func append(float value: Float32) {
        var mutableValue = value
        Swift.withUnsafeBytes(of: &mutableValue) { rawBuffer in
            append(rawBuffer.bindMemory(to: UInt8.self))
        }
    }

    func toArray<T>(type: T.Type) -> [T] {
        withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: T.self)
            return Array(buffer)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension CIImage {
    func centerCroppedToSquare() -> CIImage {
        let squareSize = min(extent.width, extent.height)
        let xOffset = extent.origin.x + (extent.width - squareSize) / 2
        let yOffset = extent.origin.y + (extent.height - squareSize) / 2
        return cropped(to: CGRect(x: xOffset, y: yOffset, width: squareSize, height: squareSize))
    }

    func cropped(toNormalizedRect box: NormalizedRect) -> CIImage {
        let clampedLeft = min(max(box.left, 0), 1)
        let clampedTop = min(max(box.top, 0), 1)
        let clampedRight = min(max(box.right, clampedLeft), 1)
        let clampedBottom = min(max(box.bottom, clampedTop), 1)
        let cropRect = CGRect(
            x: extent.origin.x + clampedLeft * extent.width,
            y: extent.origin.y + clampedTop * extent.height,
            width: max((clampedRight - clampedLeft) * extent.width, 1),
            height: max((clampedBottom - clampedTop) * extent.height, 1)
        ).integral

        let boundedCrop = cropRect.intersection(extent)
        guard !boundedCrop.isNull, !boundedCrop.isEmpty else { return self }
        return cropped(to: boundedCrop)
    }

    func resized(to size: CGSize) -> CIImage {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
