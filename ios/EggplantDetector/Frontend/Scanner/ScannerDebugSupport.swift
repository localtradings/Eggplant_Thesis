import UIKit

struct BundledDebugSampleImage {
    let filename: String
    let image: UIImage
}

func loadBundledDebugSampleImage() -> BundledDebugSampleImage? {
    let sampleCandidates: [(name: String, ext: String, subdirectory: String?)] = [
        ("leaf_spot_sample1", "jpg", nil),
        ("leaf_spot_sample2", "jpg", nil),
        ("leaf_spot_sample1", "jpg", "DebugSamples"),
        ("leaf_spot_sample2", "jpg", "DebugSamples"),
    ]

    for candidate in sampleCandidates {
        guard let sampleURL = Bundle.main.url(
            forResource: candidate.name,
            withExtension: candidate.ext,
            subdirectory: candidate.subdirectory
        ) else {
            continue
        }

        guard let image = UIImage(contentsOfFile: sampleURL.path) else {
            continue
        }

        return BundledDebugSampleImage(
            filename: sampleURL.lastPathComponent,
            image: image
        )
    }

    return nil
}

func makeBundledDebugPresentation(
    state: DiagnosisState,
    assessment: FrameAssessment,
    result: ClassificationResult?,
    filename: String
) -> BundledDebugPresentation {
    let best = result?.topResults.first
    let bestLabel = best?.label.replacingOccurrences(of: "_", with: " ") ?? "No result"
    let bestConfidence = best.map { String(format: "%.1f%%", $0.confidence * 100) } ?? "0.0%"
    let leafGuardPassed = assessment.likelyLeafRatio >= ModelContract.minLeafRatio &&
        assessment.centerLeafRatio >= ModelContract.minCenterLeafRatio
    let debugSummary = [
        "Top label: \(bestLabel)",
        "Top confidence: \(bestConfidence)",
        "Leaf ratio: \(String(format: "%.4f", assessment.likelyLeafRatio))",
        "Center leaf ratio: \(String(format: "%.4f", assessment.centerLeafRatio))",
        "Leaf guard: \(leafGuardPassed ? "passed" : "failed")",
        "Final state: \(diagnosisStateSummary(state))",
        "Source file: \(filename)"
    ].joined(separator: "\n")

    switch state {
    case let .confirmed(label, confidence, _):
        return BundledDebugPresentation(
            eyebrow: "DEBUG SAMPLE",
            title: label.replacingOccurrences(of: "_", with: " "),
            subtitle: "Bundled sample diagnosis at \(String(format: "%.1f%%", confidence * 100)).",
            details: debugSummary
        )

    case let .uncertain(_, reason):
        let subtitle: String
        switch reason {
        case .lowConfidence:
            subtitle = "The bundled sample was classified, but confidence stayed below the final diagnosis threshold."
        case .ambiguous:
            subtitle = "The bundled sample was classified, but the top labels stayed too close to finalize one diagnosis."
        default:
            subtitle = "The bundled sample was classified, but the final diagnosis stayed uncertain."
        }
        return BundledDebugPresentation(
            eyebrow: "DEBUG SAMPLE",
            title: "Bundled sample uncertain",
            subtitle: subtitle,
            details: debugSummary
        )

    case let .needsRetake(reason):
        switch reason {
        case .noLeafDetected:
            return BundledDebugPresentation(
                eyebrow: "DEBUG SAMPLE",
                title: "Bundled sample classified",
                subtitle: "\(bestLabel) scored \(bestConfidence), but the clear-leaf targeting guard failed.",
                details: debugSummary
            )

        case .increaseLight:
            return BundledDebugPresentation(
                eyebrow: "DEBUG SAMPLE",
                title: "Bundled sample blocked by lighting guard",
                subtitle: "Inference ran successfully, but the bundled sample was too dark for a final diagnosis.",
                details: debugSummary
            )

        case .reduceGlare:
            return BundledDebugPresentation(
                eyebrow: "DEBUG SAMPLE",
                title: "Bundled sample blocked by glare guard",
                subtitle: "Inference ran successfully, but the bundled sample was too bright for a final diagnosis.",
                details: debugSummary
            )

        default:
            return BundledDebugPresentation(
                eyebrow: "DEBUG SAMPLE",
                title: reason.title,
                subtitle: "Bundled sample inference ran, but the final diagnosis stayed in guidance mode.",
                details: debugSummary
            )
        }
    }
}

func diagnosisStateSummary(_ state: DiagnosisState) -> String {
    switch state {
    case let .confirmed(label, _, _):
        return "confirmed (\(label))"
    case let .uncertain(_, reason):
        return "uncertain (\(reason))"
    case let .needsRetake(reason):
        return "needsRetake (\(reason))"
    }
}
