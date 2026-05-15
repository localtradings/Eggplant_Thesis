import UIKit

final class AboutAppViewController: AppInfoBaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About"
        renderContent()
    }

    private func renderContent() {
        stackView.addArrangedSubview(makeCard(
            title: "Eggplant Disease Detector",
            body: "This iOS app helps screen eggplant leaves offline with the bundled TensorFlow Lite model.",
            iconName: "leaf.fill"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "Supported labels",
            body: supportedDisplayNames,
            iconName: "list.bullet.rectangle.fill"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "Local database",
            body: "Scan History uses an on-device SQLite database named eggplant_database.sqlite for confirmed saved diagnoses. The old JSON history file is only read once for migration and is not deleted.",
            iconName: "internaldrive.fill"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "Important note",
            body: "This app is for assistance only. It does not replace advice from an agriculture expert or local plant health service.",
            iconName: "info.circle.fill"
        ))
    }

    private var supportedDisplayNames: String {
        guard let store = try? DiagnosisSummaryStore(),
              let items = try? store.loadDiseaseGuideItems(),
              !items.isEmpty else {
            return DiseaseCatalog.items.map { $0.displayName }.joined(separator: "\n")
        }
        return items.map { $0.displayName }.joined(separator: "\n")
    }
}
