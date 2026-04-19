import Foundation

enum DiagnosisSummarySource: String, Codable {
    case cameraSelectedCrop
}

enum SavedDiagnosisStateKind: String, Codable {
    case confirmed
    case uncertain
    case needsRetake
}

enum SavedCaptureMode: String, Codable {
    case live
}

struct SavedNormalizedRect: Codable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    init(_ rect: NormalizedRect) {
        left = Double(rect.left)
        top = Double(rect.top)
        right = Double(rect.right)
        bottom = Double(rect.bottom)
    }
}

struct SavedDiagnosisSummary: Codable {
    let id: UUID
    let createdAt: Date
    let source: DiagnosisSummarySource
    let mode: SavedCaptureMode
    let targetBox: SavedNormalizedRect
    let finalStateKind: SavedDiagnosisStateKind
    let diagnosisLabel: String?
    let confidence: Float?
    let topLabel: String?
    let topConfidence: Float?
    let meanBrightness: Float
    let likelyLeafRatio: Float
    let centerLeafRatio: Float
    let leafGuardPassed: Bool
    let reason: String?
}

final class DiagnosisSummaryStore {
    static let filename = "diagnosis_summaries.json"

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = documentsURL.appendingPathComponent(Self.filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    @discardableResult
    func save(_ summary: SavedDiagnosisSummary) throws -> URL {
        var summaries = try load()
        summaries.append(summary)
        let data = try encoder.encode(summaries)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func load() throws -> [SavedDiagnosisSummary] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([SavedDiagnosisSummary].self, from: data)
    }
}
