import UIKit

enum AppInfoStyle {
    static let backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)
    static let cardColor = UIColor.white.withAlphaComponent(0.94)
    static let green = UIColor(red: 0.39, green: 0.58, blue: 0.33, alpha: 1)
    static let darkText = UIColor(red: 0.20, green: 0.25, blue: 0.18, alpha: 1)
    static let mutedText = UIColor(red: 0.33, green: 0.37, blue: 0.30, alpha: 1)

    static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func configureCard(_ view: UIView, radius: CGFloat = 18) {
        view.backgroundColor = cardColor
        view.layer.cornerRadius = radius
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.06).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: 0, height: 5)
    }
}

class AppInfoBaseViewController: UIViewController {
    let scrollView = UIScrollView()
    let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBase()
    }

    func configureBase() {
        view.backgroundColor = AppInfoStyle.backgroundColor
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closePressed)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    func makeCard(title: String, body: String, iconName: String? = nil) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        AppInfoStyle.configureCard(card)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = AppInfoStyle.roundedFont(size: 18, weight: .semibold)
        titleLabel.textColor = AppInfoStyle.darkText
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.text = body
        bodyLabel.font = AppInfoStyle.roundedFont(size: 14, weight: .regular)
        bodyLabel.textColor = AppInfoStyle.mutedText
        bodyLabel.numberOfLines = 0

        let verticalStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        verticalStack.translatesAutoresizingMaskIntoConstraints = false
        verticalStack.axis = .vertical
        verticalStack.spacing = 7

        if let iconName {
            let iconWrap = UIView()
            iconWrap.translatesAutoresizingMaskIntoConstraints = false
            iconWrap.backgroundColor = UIColor(red: 0.92, green: 0.94, blue: 0.86, alpha: 1)
            iconWrap.layer.cornerRadius = 18

            let icon = UIImageView(image: UIImage(systemName: iconName))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = AppInfoStyle.green
            icon.contentMode = .scaleAspectFit

            iconWrap.addSubview(icon)
            card.addSubview(iconWrap)
            card.addSubview(verticalStack)

            NSLayoutConstraint.activate([
                iconWrap.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                iconWrap.widthAnchor.constraint(equalToConstant: 42),
                iconWrap.heightAnchor.constraint(equalToConstant: 42),
                icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 22),
                icon.heightAnchor.constraint(equalToConstant: 22),

                verticalStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
                verticalStack.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 14),
                verticalStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                verticalStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
            ])
        } else {
            card.addSubview(verticalStack)
            NSLayoutConstraint.activate([
                verticalStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                verticalStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                verticalStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                verticalStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
            ])
        }

        return card
    }

    func bulletList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }
}
