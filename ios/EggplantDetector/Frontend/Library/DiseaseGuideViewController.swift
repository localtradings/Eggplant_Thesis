import UIKit

final class DiseaseGuideViewController: AppInfoBaseViewController, UISearchBarDelegate {
    private let searchBar = UISearchBar()
    private let store: DiagnosisSummaryStore?
    private var allItems: [DiseaseGuideItem] = []
    private var filteredItems: [DiseaseGuideItem] = []

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
        title = "Library"
        configureSearch()
        loadItems()
        renderItems()
    }

    private func configureSearch() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search supported labels"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.accessibilityLabel = "Search disease guide"
        stackView.addArrangedSubview(searchBar)
    }

    private func loadItems() {
        do {
            allItems = try store?.loadDiseaseGuideItems() ?? []
        } catch {
            allItems = []
        }
        filteredItems = allItems
    }

    private func renderItems() {
        stackView.arrangedSubviews
            .filter { $0 !== searchBar }
            .forEach {
                stackView.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

        let header = makeCard(
            title: "Supported eggplant results",
            body: "This guide only covers the labels bundled with the app model: \(supportedLabelText).",
            iconName: "leaf.fill"
        )
        stackView.addArrangedSubview(header)

        if filteredItems.isEmpty {
            stackView.addArrangedSubview(makeCard(
                title: "No matching label",
                body: "Try healthy, leaf spot, mosaic, pest, white mold, or wilt.",
                iconName: "magnifyingglass"
            ))
            return
        }

        filteredItems.forEach { item in
            stackView.addArrangedSubview(makeGuideCard(for: item))
        }
    }

    private func makeGuideCard(for item: DiseaseGuideItem) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        AppInfoStyle.configureCard(card)

        let categoryLabel = UILabel()
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.text = item.category.uppercased()
        categoryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        categoryLabel.textColor = item.isHealthy ? AppInfoStyle.green : UIColor(red: 0.55, green: 0.38, blue: 0.18, alpha: 1)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = item.displayName
        titleLabel.font = AppInfoStyle.roundedFont(size: 20, weight: .bold)
        titleLabel.textColor = AppInfoStyle.darkText
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.text = item.overview
        bodyLabel.font = AppInfoStyle.roundedFont(size: 14, weight: .regular)
        bodyLabel.textColor = AppInfoStyle.mutedText
        bodyLabel.numberOfLines = 0

        let scanLabel = makeSmallSection(title: "Scan tips", body: bulletList(item.scanTips))
        let nextLabel = makeSmallSection(title: "Safe next steps", body: bulletList(item.nextSteps))

        let stack = UIStackView(arrangedSubviews: [categoryLabel, titleLabel, bodyLabel, scanLabel, nextLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 9

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private var supportedLabelText: String {
        let labels = allItems.isEmpty ? DiseaseCatalog.supportedLabels : allItems.map(\.label)
        return labels.joined(separator: ", ")
    }

    private func makeSmallSection(title: String, body: String) -> UILabel {
        let label = UILabel()
        label.text = "\(title)\n\(body)"
        label.font = AppInfoStyle.roundedFont(size: 13, weight: .regular)
        label.textColor = AppInfoStyle.mutedText
        label.numberOfLines = 0
        return label
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter {
                $0.displayName.lowercased().contains(query) ||
                    $0.label.lowercased().contains(query) ||
                    $0.category.lowercased().contains(query)
            }
        }
        renderItems()
    }
}
