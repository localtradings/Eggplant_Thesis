import Foundation
import SQLite3

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
    case photo

    var displayName: String {
        switch self {
        case .live:
            return "Live scan"
        case .photo:
            return "Photo diagnosis"
        }
    }
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

    init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
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
    static let filename = "eggplant_database.sqlite"
    static let legacyJSONFilename = "diagnosis_summaries.json"

    enum StoreError: LocalizedError {
        case unsupportedLabel
        case nonConfirmedSummary

        var errorDescription: String? {
            switch self {
            case .unsupportedLabel:
                return "Only supported model labels can be saved."
            case .nonConfirmedSummary:
                return "Only confirmed diagnoses can be saved."
            }
        }
    }

    private let databaseURL: URL
    private let legacyJSONURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let database: SQLiteDatabase

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        databaseURL = documentsURL.appendingPathComponent(Self.filename)
        legacyJSONURL = documentsURL.appendingPathComponent(Self.legacyJSONFilename)
        database = try SQLiteDatabase(url: databaseURL)
        try createSchema()
        try seedReferenceData()
        try importLegacyJSONIfNeeded()
    }

    @discardableResult
    func save(_ summary: SavedDiagnosisSummary) throws -> URL {
        guard summary.finalStateKind == .confirmed else {
            throw StoreError.nonConfirmedSummary
        }
        guard DiseaseCatalog.isSupportedLabel(summary.diagnosisLabel) else {
            throw StoreError.unsupportedLabel
        }

        try database.transaction {
            try insert(summary)
        }
        return databaseURL
    }

    func load() throws -> [SavedDiagnosisSummary] {
        try querySummaries(
            """
            SELECT summaryID, dateTimeCaptured, source, captureMode, targetLeft, targetTop,
                   targetRight, targetBottom, finalStateKind, diagnosisLabel, confidenceScore,
                   topLabel, topConfidence, meanBrightness, likelyLeafRatio, centerLeafRatio,
                   leafGuardPassed, reason
            FROM scans
            ORDER BY dateTimeCaptured DESC
            """
        )
    }

    func loadConfirmedSupported() throws -> [SavedDiagnosisSummary] {
        let quotedLabels = DiseaseCatalog.supportedLabels.map { "'\($0)'" }.joined(separator: ", ")
        return try querySummaries(
            """
            SELECT summaryID, dateTimeCaptured, source, captureMode, targetLeft, targetTop,
                   targetRight, targetBottom, finalStateKind, diagnosisLabel, confidenceScore,
                   topLabel, topConfidence, meanBrightness, likelyLeafRatio, centerLeafRatio,
                   leafGuardPassed, reason
            FROM scans
            WHERE finalStateKind = 'confirmed'
              AND diagnosisLabel IN (\(quotedLabels))
            ORDER BY dateTimeCaptured DESC
            """
        )
    }

    func loadDiseaseGuideItems() throws -> [DiseaseGuideItem] {
        let statement = try database.prepare(
            """
            SELECT d.label, d.diseaseName, d.category, d.diseaseDescription,
                   GROUP_CONCAT(t.treatmentProcedures, char(10) || char(31) || char(10)) AS nextSteps
            FROM diseases d
            LEFT JOIN disease_treatments dt ON dt.diseaseID = d.diseaseID
            LEFT JOIN treatments t ON t.treatmentID = dt.treatmentID
            GROUP BY d.diseaseID, d.label, d.diseaseName, d.category, d.diseaseDescription
            ORDER BY d.diseaseID ASC
            """
        )

        var items: [DiseaseGuideItem] = []
        while try statement.step() == SQLITE_ROW {
            guard let label = statement.columnString(0),
                  let displayName = statement.columnString(1),
                  let category = statement.columnString(2),
                  let overview = statement.columnString(3)
            else {
                continue
            }

            let fallback = DiseaseCatalog.item(for: label)
            let nextSteps = statement.columnString(4)?
                .components(separatedBy: "\n\u{1F}\n")
                .flatMap { $0.components(separatedBy: "\n") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? fallback?.nextSteps ?? []
            items.append(DiseaseGuideItem(
                label: label,
                displayName: displayName,
                category: category,
                overview: overview,
                scanTips: fallback?.scanTips ?? [],
                nextSteps: nextSteps
            ))
        }
        return items
    }

    private func createSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS diseases (
                diseaseID INTEGER PRIMARY KEY,
                label TEXT NOT NULL UNIQUE,
                diseaseName TEXT NOT NULL,
                diseaseDescription TEXT NOT NULL,
                category TEXT NOT NULL,
                dateAdded INTEGER NOT NULL,
                dateUpdated INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS treatments (
                treatmentID INTEGER PRIMARY KEY,
                treatmentName TEXT NOT NULL,
                treatmentProcedures TEXT NOT NULL,
                dateAdded INTEGER NOT NULL,
                dateUpdated INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS disease_treatments (
                diseaseID INTEGER NOT NULL,
                treatmentID INTEGER NOT NULL,
                PRIMARY KEY (diseaseID, treatmentID),
                FOREIGN KEY (diseaseID) REFERENCES diseases(diseaseID) ON DELETE CASCADE,
                FOREIGN KEY (treatmentID) REFERENCES treatments(treatmentID) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS scan_sessions (
                sessionID TEXT PRIMARY KEY,
                startingTimestamp INTEGER NOT NULL,
                endingTimestamp INTEGER NOT NULL DEFAULT 0,
                totalLeaves INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS scans (
                scanID INTEGER PRIMARY KEY AUTOINCREMENT,
                summaryID TEXT NOT NULL UNIQUE,
                parentSessionID TEXT NOT NULL,
                imagePath TEXT NOT NULL DEFAULT '',
                dateTimeCaptured INTEGER NOT NULL,
                confidenceScore REAL NOT NULL,
                captureMode TEXT NOT NULL,
                diseaseID INTEGER,
                diagnosisLabel TEXT NOT NULL,
                finalStateKind TEXT NOT NULL,
                source TEXT NOT NULL,
                topLabel TEXT,
                topConfidence REAL,
                meanBrightness REAL NOT NULL,
                likelyLeafRatio REAL NOT NULL,
                centerLeafRatio REAL NOT NULL,
                leafGuardPassed INTEGER NOT NULL,
                targetLeft REAL NOT NULL,
                targetTop REAL NOT NULL,
                targetRight REAL NOT NULL,
                targetBottom REAL NOT NULL,
                reason TEXT,
                FOREIGN KEY (parentSessionID) REFERENCES scan_sessions(sessionID) ON DELETE CASCADE,
                FOREIGN KEY (diseaseID) REFERENCES diseases(diseaseID)
            );

            CREATE INDEX IF NOT EXISTS idx_scans_dateTimeCaptured ON scans(dateTimeCaptured DESC);
            CREATE INDEX IF NOT EXISTS idx_scans_diagnosisLabel ON scans(diagnosisLabel);
            CREATE INDEX IF NOT EXISTS idx_scan_sessions_startingTimestamp ON scan_sessions(startingTimestamp DESC);
            """
        )
    }

    private func seedReferenceData() throws {
        let now = milliseconds(from: Date())
        try database.transaction {
            for (index, item) in DiseaseCatalog.items.enumerated() {
                let id = Int64(index + 1)
                let diseaseStatement = try database.prepare(
                    """
                    INSERT OR IGNORE INTO diseases
                    (diseaseID, label, diseaseName, diseaseDescription, category, dateAdded, dateUpdated)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """
                )
                try diseaseStatement.bind(id, at: 1)
                try diseaseStatement.bind(item.label, at: 2)
                try diseaseStatement.bind(item.displayName, at: 3)
                try diseaseStatement.bind(item.overview, at: 4)
                try diseaseStatement.bind(item.category, at: 5)
                try diseaseStatement.bind(now, at: 6)
                try diseaseStatement.bind(now, at: 7)
                try diseaseStatement.step()

                let treatmentStatement = try database.prepare(
                    """
                    INSERT OR IGNORE INTO treatments
                    (treatmentID, treatmentName, treatmentProcedures, dateAdded, dateUpdated)
                    VALUES (?, ?, ?, ?, ?)
                    """
                )
                try treatmentStatement.bind(id, at: 1)
                try treatmentStatement.bind("\(item.displayName) guidance", at: 2)
                try treatmentStatement.bind(item.nextSteps.joined(separator: "\n"), at: 3)
                try treatmentStatement.bind(now, at: 4)
                try treatmentStatement.bind(now, at: 5)
                try treatmentStatement.step()

                let crossRefStatement = try database.prepare(
                    """
                    INSERT OR IGNORE INTO disease_treatments (diseaseID, treatmentID)
                    VALUES (?, ?)
                    """
                )
                try crossRefStatement.bind(id, at: 1)
                try crossRefStatement.bind(id, at: 2)
                try crossRefStatement.step()
            }
        }
    }

    private func importLegacyJSONIfNeeded() throws {
        guard try metadataValue(for: "json_history_imported_v1") != "true" else {
            return
        }

        let summaries: [SavedDiagnosisSummary]
        if fileManager.fileExists(atPath: legacyJSONURL.path),
           let data = try? Data(contentsOf: legacyJSONURL),
           let decoded = try? decoder.decode([SavedDiagnosisSummary].self, from: data) {
            summaries = decoded
        } else {
            summaries = []
        }

        try database.transaction {
            for summary in summaries where summary.finalStateKind == .confirmed && DiseaseCatalog.isSupportedLabel(summary.diagnosisLabel) {
                try insert(summary)
            }
            try setMetadata("json_history_imported_v1", value: "true")
        }
    }

    private func insert(_ summary: SavedDiagnosisSummary) throws {
        guard summary.finalStateKind == .confirmed else {
            throw StoreError.nonConfirmedSummary
        }
        let normalizedLabel = DiseaseCatalog.normalizedLabel(summary.diagnosisLabel ?? "")
        guard DiseaseCatalog.isSupportedLabel(normalizedLabel) else {
            throw StoreError.unsupportedLabel
        }

        let sessionID = sessionID(for: summary)
        let timestamp = milliseconds(from: summary.createdAt)
        let sessionStatement = try database.prepare(
            """
            INSERT OR IGNORE INTO scan_sessions
            (sessionID, startingTimestamp, endingTimestamp, totalLeaves)
            VALUES (?, ?, ?, ?)
            """
        )
        try sessionStatement.bind(sessionID, at: 1)
        try sessionStatement.bind(timestamp, at: 2)
        try sessionStatement.bind(timestamp, at: 3)
        try sessionStatement.bind(Int64(1), at: 4)
        try sessionStatement.step()

        let scanStatement = try database.prepare(
            """
            INSERT OR IGNORE INTO scans
            (summaryID, parentSessionID, imagePath, dateTimeCaptured, confidenceScore,
             captureMode, diseaseID, diagnosisLabel, finalStateKind, source, topLabel,
             topConfidence, meanBrightness, likelyLeafRatio, centerLeafRatio,
             leafGuardPassed, targetLeft, targetTop, targetRight, targetBottom, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        try scanStatement.bind(summary.id.uuidString, at: 1)
        try scanStatement.bind(sessionID, at: 2)
        try scanStatement.bind("", at: 3)
        try scanStatement.bind(timestamp, at: 4)
        try scanStatement.bind(Double(summary.confidence ?? summary.topConfidence ?? 0), at: 5)
        try scanStatement.bind(summary.mode.rawValue, at: 6)
        try scanStatement.bind(try diseaseID(for: normalizedLabel), at: 7)
        try scanStatement.bind(normalizedLabel, at: 8)
        try scanStatement.bind(summary.finalStateKind.rawValue, at: 9)
        try scanStatement.bind(summary.source.rawValue, at: 10)
        try scanStatement.bind(summary.topLabel.map(DiseaseCatalog.normalizedLabel), at: 11)
        try scanStatement.bind(summary.topConfidence.map(Double.init), at: 12)
        try scanStatement.bind(Double(summary.meanBrightness), at: 13)
        try scanStatement.bind(Double(summary.likelyLeafRatio), at: 14)
        try scanStatement.bind(Double(summary.centerLeafRatio), at: 15)
        try scanStatement.bind(summary.leafGuardPassed, at: 16)
        try scanStatement.bind(summary.targetBox.left, at: 17)
        try scanStatement.bind(summary.targetBox.top, at: 18)
        try scanStatement.bind(summary.targetBox.right, at: 19)
        try scanStatement.bind(summary.targetBox.bottom, at: 20)
        try scanStatement.bind(summary.reason, at: 21)
        try scanStatement.step()
    }

    private func querySummaries(_ sql: String) throws -> [SavedDiagnosisSummary] {
        let statement = try database.prepare(sql)
        var summaries: [SavedDiagnosisSummary] = []
        while try statement.step() == SQLITE_ROW {
            guard let idString = statement.columnString(0),
                  let id = UUID(uuidString: idString)
            else {
                continue
            }

            let source = statement.columnString(2).flatMap(DiagnosisSummarySource.init(rawValue:)) ?? .cameraSelectedCrop
            let mode = statement.columnString(3).flatMap(SavedCaptureMode.init(rawValue:)) ?? .live
            let state = statement.columnString(8).flatMap(SavedDiagnosisStateKind.init(rawValue:)) ?? .confirmed
            let diagnosisLabel = statement.columnString(9)
            let topLabel = statement.columnString(11)
            let topConfidence = statement.isNull(12) ? nil : Float(statement.columnDouble(12))
            summaries.append(SavedDiagnosisSummary(
                id: id,
                createdAt: date(fromMilliseconds: statement.columnInt64(1)),
                source: source,
                mode: mode,
                targetBox: SavedNormalizedRect(
                    left: statement.columnDouble(4),
                    top: statement.columnDouble(5),
                    right: statement.columnDouble(6),
                    bottom: statement.columnDouble(7)
                ),
                finalStateKind: state,
                diagnosisLabel: diagnosisLabel,
                confidence: Float(statement.columnDouble(10)),
                topLabel: topLabel,
                topConfidence: topConfidence,
                meanBrightness: Float(statement.columnDouble(13)),
                likelyLeafRatio: Float(statement.columnDouble(14)),
                centerLeafRatio: Float(statement.columnDouble(15)),
                leafGuardPassed: statement.columnBool(16),
                reason: statement.columnString(17)
            ))
        }
        return summaries
    }

    private func diseaseID(for label: String) throws -> Int64? {
        let statement = try database.prepare("SELECT diseaseID FROM diseases WHERE label = ? LIMIT 1")
        try statement.bind(label, at: 1)
        guard try statement.step() == SQLITE_ROW else {
            return nil
        }
        return statement.columnInt64(0)
    }

    private func metadataValue(for key: String) throws -> String? {
        let statement = try database.prepare("SELECT value FROM metadata WHERE key = ? LIMIT 1")
        try statement.bind(key, at: 1)
        guard try statement.step() == SQLITE_ROW else {
            return nil
        }
        return statement.columnString(0)
    }

    private func setMetadata(_ key: String, value: String) throws {
        let statement = try database.prepare(
            """
            INSERT INTO metadata (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """
        )
        try statement.bind(key, at: 1)
        try statement.bind(value, at: 2)
        try statement.step()
    }

    private func sessionID(for summary: SavedDiagnosisSummary) -> String {
        "session-\(summary.id.uuidString)"
    }

    private func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}
