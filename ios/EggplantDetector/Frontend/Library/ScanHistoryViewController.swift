import UIKit

final class ScanHistoryViewController: AppInfoBaseViewController {
    private let store: DiagnosisSummaryStore?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: DiagnosisSummaryStore? = try? DiagnosisSummaryStore()) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan History"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderHistory()
    }

    private func renderHistory() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let store else {
            stackView.addArrangedSubview(makeCard(
                title: "History unavailable",
                body: "The local database file could not be opened on this device.",
                iconName: "exclamationmark.triangle.fill"
            ))
            return
        }

        do {
            let summaries = try store.loadConfirmedSupported().sorted { $0.createdAt > $1.createdAt }
            if summaries.isEmpty {
                stackView.addArrangedSubview(makeCard(
                    title: "No confirmed scans yet",
                    body: "Confirmed live or photo diagnoses will appear here after you save them from the scanner.",
                    iconName: "clock.fill"
                ))
                return
            }

            stackView.addArrangedSubview(makeCard(
                title: "\(summaries.count) saved scan\(summaries.count == 1 ? "" : "s")",
                body: "Newest confirmed eggplant leaf diagnoses are shown first.",
                iconName: "checkmark.seal.fill"
            ))

            summaries.forEach { summary in
                stackView.addArrangedSubview(makeHistoryCard(summary))
            }
        } catch {
            stackView.addArrangedSubview(makeCard(
                title: "Could not read history",
                body: "The app kept your local SQLite database file, but this version could not read the saved scan rows.",
                iconName: "doc.text.magnifyingglass"
            ))
        }
    }

    private func makeHistoryCard(_ summary: SavedDiagnosisSummary) -> UIView {
        let label = summary.diagnosisLabel ?? summary.topLabel
        let confidence = summary.confidence ?? summary.topConfidence
        let title = DiseaseCatalog.displayName(for: label)
        let confidenceText = confidence.map { String(format: "%.0f%% confidence", $0 * 100) } ?? "Confidence unavailable"
        let metrics = String(
            format: "Brightness %.0f%%  Leaf %.0f%%  Center %.0f%%",
            summary.meanBrightness * 100,
            summary.likelyLeafRatio * 100,
            summary.centerLeafRatio * 100
        )
        let body = [
            confidenceText,
            summary.mode.displayName,
            dateFormatter.string(from: summary.createdAt),
            metrics
        ].joined(separator: "\n")

        return makeCard(title: title, body: body, iconName: "leaf.circle.fill")
    }
}
