import Foundation

struct DiseaseGuideItem: Equatable {
    let label: String
    let displayName: String
    let category: String
    let overview: String
    let scanTips: [String]
    let nextSteps: [String]

    var isHealthy: Bool {
        label == "healthy"
    }
}

enum DiseaseCatalog {
    static let supportedLabels = [
        "healthy",
        "leaf_spot",
        "mosaic",
        "pest",
        "white_mold",
        "wilt"
    ]

    static let items: [DiseaseGuideItem] = [
        DiseaseGuideItem(
            label: "healthy",
            displayName: "Healthy leaf",
            category: "Normal result",
            overview: "The scanned eggplant leaf looks close to the app's healthy reference class.",
            scanTips: [
                "Keep checking new leaves under clear light.",
                "Scan again if the leaf later shows spots, curling, mold, or wilting."
            ],
            nextSteps: [
                "Continue normal plant care.",
                "Keep leaves dry and remove old plant debris around the crop."
            ]
        ),
        DiseaseGuideItem(
            label: "leaf_spot",
            displayName: "Leaf spot",
            category: "Possible disease",
            overview: "Leaf spot can appear as dark, round, or irregular spots on eggplant leaves.",
            scanTips: [
                "Center one spotted leaf in the frame.",
                "Avoid glare so the spot edges stay visible."
            ],
            nextSteps: [
                "Remove badly affected leaves when safe to do so.",
                "Improve airflow and avoid wetting leaves during watering."
            ]
        ),
        DiseaseGuideItem(
            label: "mosaic",
            displayName: "Mosaic",
            category: "Possible disease",
            overview: "Mosaic patterns often look like mixed light and dark patches, mottling, or distorted leaf growth.",
            scanTips: [
                "Scan a leaf with clear mottled color patches.",
                "Use bright shade instead of direct sun."
            ],
            nextSteps: [
                "Separate plants with strong mosaic symptoms when possible.",
                "Control insects that may spread plant viruses."
            ]
        ),
        DiseaseGuideItem(
            label: "pest",
            displayName: "Pest damage",
            category: "Possible pest issue",
            overview: "Pest damage may show as holes, scraped leaf tissue, bite marks, or stressed leaf areas.",
            scanTips: [
                "Scan the damaged area and the surrounding leaf.",
                "Retake if the model sees mostly soil, hand, or background."
            ],
            nextSteps: [
                "Check under leaves for insects or eggs.",
                "Use safe pest control advice from a local agriculture expert."
            ]
        ),
        DiseaseGuideItem(
            label: "white_mold",
            displayName: "White mold",
            category: "Possible disease",
            overview: "White mold can look like pale fuzzy growth or light moldy patches on affected leaf tissue.",
            scanTips: [
                "Make sure the white area is in focus.",
                "Scan in even light so pale mold is not washed out."
            ],
            nextSteps: [
                "Avoid overhead watering and reduce excess humidity.",
                "Remove affected plant material carefully when advised."
            ]
        ),
        DiseaseGuideItem(
            label: "wilt",
            displayName: "Wilt",
            category: "Possible disease or stress",
            overview: "Wilt appears as drooping, limp, or collapsed leaves even when the plant should be firm.",
            scanTips: [
                "Scan a drooping leaf attached to the plant.",
                "Retake if the frame is too dark or only shows stems."
            ],
            nextSteps: [
                "Check soil moisture and root stress.",
                "Ask a local expert if wilting continues after watering is corrected."
            ]
        )
    ]

    static func isSupportedLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return supportedLabels.contains(normalizedLabel(label))
    }

    static func item(for label: String?) -> DiseaseGuideItem? {
        guard let label else { return nil }
        let normalized = normalizedLabel(label)
        return items.first { $0.label == normalized }
    }

    static func displayName(for label: String?) -> String {
        item(for: label)?.displayName ?? "Unsupported result"
    }

    static func normalizedLabel(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}
