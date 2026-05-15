import UIKit

final class HomeViewController: UIViewController {
    private let backgroundView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerIconView = UIImageView(image: UIImage(systemName: "leaf.fill"))
    private let headerTitleLabel = UILabel()
    private let heroCard = UIView()
    private let heroBackgroundImageView = UIImageView(image: UIImage(named: "HeroIllustration"))
    private let heroTextStack = UIStackView()
    private let heroTitleLabel = UILabel()
    private let heroSubtitleLabel = UILabel()
    private let heroTextBackdropView = UIView()
    private let actionCard = UIView()
    private let startScanningButton = UIButton(type: .system)
    private let uploadImageButton = UIButton(type: .system)
    private let infoCard = UIView()
    private let infoIconBadge = UILabel()
    private let infoTitleLabel = UILabel()
    private let infoBodyLabel = UILabel()
    private let featuresGrid = UIStackView()
    private let disclaimerLabel = UILabel()
    private let bottomBar = UIView()
    private let scanButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    private func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func configure() {
        view.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)

        configureScrollView()
        configureHeader()
        configureHero()
        configureActionCard()
        configureInfoCard()
        configureFeatureGrid()
        configureDisclaimer()
        configureBottomBar()
        buildLayout()
    }

    private func configureScrollView() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        contentView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(backgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
    }

    private func configureHeader() {
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.tintColor = UIColor(red: 0.39, green: 0.58, blue: 0.33, alpha: 1)
        headerIconView.contentMode = .scaleAspectFit

        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerTitleLabel.text = "Eggplant Disease Detector"
        headerTitleLabel.font = roundedFont(size: 21, weight: .semibold)
        headerTitleLabel.textColor = UIColor(red: 0.23, green: 0.29, blue: 0.21, alpha: 1)
        headerTitleLabel.numberOfLines = 1
    }

    private func configureHero() {
        heroCard.translatesAutoresizingMaskIntoConstraints = false
        heroCard.backgroundColor = UIColor(red: 0.94, green: 0.95, blue: 0.86, alpha: 1)
        heroCard.layer.cornerRadius = 26
        heroCard.layer.masksToBounds = true

        heroBackgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        heroBackgroundImageView.contentMode = .scaleAspectFill
        heroBackgroundImageView.clipsToBounds = true

        let glow = CAGradientLayer()
        glow.colors = [
            UIColor(red: 0.99, green: 0.98, blue: 0.90, alpha: 0.94).cgColor,
            UIColor(red: 0.97, green: 0.95, blue: 0.78, alpha: 0.55).cgColor,
            UIColor(red: 0.95, green: 0.95, blue: 0.84, alpha: 0.08).cgColor
        ]
        glow.startPoint = CGPoint(x: 0, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 0.5)
        glow.frame = CGRect(x: 0, y: 0, width: 800, height: 320)

        let glowView = UIView()
        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.isUserInteractionEnabled = false
        glowView.layer.insertSublayer(glow, at: 0)

        heroTextBackdropView.translatesAutoresizingMaskIntoConstraints = false
        heroTextBackdropView.backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.80, alpha: 0.48)
        heroTextBackdropView.layer.cornerRadius = 22

        heroTextStack.translatesAutoresizingMaskIntoConstraints = false
        heroTextStack.axis = .vertical
        heroTextStack.spacing = 7
        heroTextStack.alignment = .leading

        heroTitleLabel.text = "Detect possible\neggplant diseases"
        heroTitleLabel.font = roundedFont(size: 19, weight: .semibold)
        heroTitleLabel.textColor = UIColor(red: 0.23, green: 0.29, blue: 0.21, alpha: 1)
        heroTitleLabel.numberOfLines = 2
        heroTitleLabel.lineBreakMode = .byWordWrapping

        heroSubtitleLabel.text = "Scan an eggplant leaf\nusing your camera\nfor quick analysis."
        heroSubtitleLabel.font = roundedFont(size: 12.2, weight: .regular)
        heroSubtitleLabel.textColor = UIColor(red: 0.27, green: 0.30, blue: 0.23, alpha: 0.9)
        heroSubtitleLabel.numberOfLines = 3

        heroTextStack.addArrangedSubview(heroTitleLabel)
        heroTextStack.addArrangedSubview(heroSubtitleLabel)
        heroCard.addSubview(heroBackgroundImageView)
        heroCard.addSubview(glowView)
        heroCard.addSubview(heroTextBackdropView)
        heroCard.addSubview(heroTextStack)

        NSLayoutConstraint.activate([
            heroBackgroundImageView.topAnchor.constraint(equalTo: heroCard.topAnchor),
            heroBackgroundImageView.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor),
            heroBackgroundImageView.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor),
            heroBackgroundImageView.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor),

            glowView.topAnchor.constraint(equalTo: heroCard.topAnchor),
            glowView.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor),
            glowView.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor),
            glowView.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor),

            heroTextBackdropView.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 16),
            heroTextBackdropView.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 14),
            heroTextBackdropView.widthAnchor.constraint(equalToConstant: 168),
            heroTextBackdropView.heightAnchor.constraint(equalToConstant: 120)
        ])

        glowView.layoutIfNeeded()
        glow.frame = CGRect(x: 0, y: 0, width: 800, height: 320)
    }

    private func configureActionCard() {
        actionCard.translatesAutoresizingMaskIntoConstraints = false
        actionCard.backgroundColor = UIColor.white.withAlphaComponent(0.88)
        actionCard.layer.cornerRadius = 28
        actionCard.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        actionCard.layer.shadowOpacity = 1
        actionCard.layer.shadowRadius = 18
        actionCard.layer.shadowOffset = CGSize(width: 0, height: 8)

        configurePrimaryButton(startScanningButton, title: "Start Scanning", filled: true)
        startScanningButton.addTarget(self, action: #selector(startScanningPressed), for: .touchUpInside)

        configurePrimaryButton(uploadImageButton, title: "Upload Image", filled: false)
        uploadImageButton.addTarget(self, action: #selector(uploadImagePressed), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [startScanningButton, uploadImageButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10

        actionCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: actionCard.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: actionCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: actionCard.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: actionCard.bottomAnchor, constant: -16),
            startScanningButton.heightAnchor.constraint(equalToConstant: 58),
            uploadImageButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureInfoCard() {
        infoCard.translatesAutoresizingMaskIntoConstraints = false
        infoCard.backgroundColor = UIColor(red: 0.94, green: 0.95, blue: 0.83, alpha: 1)
        infoCard.layer.cornerRadius = 24
        infoCard.layer.masksToBounds = true

        infoIconBadge.translatesAutoresizingMaskIntoConstraints = false
        infoIconBadge.text = "🍆"
        infoIconBadge.textAlignment = .center
        infoIconBadge.font = .systemFont(ofSize: 24)
        infoIconBadge.backgroundColor = .white
        infoIconBadge.layer.cornerRadius = 18
        infoIconBadge.layer.masksToBounds = true

        infoTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoTitleLabel.text = "Eggplant Only"
        infoTitleLabel.font = roundedFont(size: 17, weight: .semibold)
        infoTitleLabel.textColor = UIColor(red: 0.22, green: 0.28, blue: 0.20, alpha: 1)

        infoBodyLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBodyLabel.text = "This app currently supports eggplant leaf scanning only. Please take clear photos to ensure accurate results."
        infoBodyLabel.font = roundedFont(size: 11.6, weight: .regular)
        infoBodyLabel.textColor = UIColor(red: 0.24, green: 0.28, blue: 0.21, alpha: 0.92)
        infoBodyLabel.numberOfLines = 3

        infoCard.addSubview(infoIconBadge)
        infoCard.addSubview(infoTitleLabel)
        infoCard.addSubview(infoBodyLabel)

        NSLayoutConstraint.activate([
            infoIconBadge.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 12),
            infoIconBadge.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            infoIconBadge.widthAnchor.constraint(equalToConstant: 34),
            infoIconBadge.heightAnchor.constraint(equalToConstant: 34),

            infoTitleLabel.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 12),
            infoTitleLabel.leadingAnchor.constraint(equalTo: infoIconBadge.trailingAnchor, constant: 12),
            infoTitleLabel.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),

            infoBodyLabel.topAnchor.constraint(equalTo: infoTitleLabel.bottomAnchor, constant: 6),
            infoBodyLabel.leadingAnchor.constraint(equalTo: infoTitleLabel.leadingAnchor),
            infoBodyLabel.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            infoBodyLabel.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -14)
        ])
    }

    private func configureFeatureGrid() {
        featuresGrid.translatesAutoresizingMaskIntoConstraints = false
        featuresGrid.axis = .vertical
        featuresGrid.spacing = 8

        let topRow = UIStackView(arrangedSubviews: [
            makeFeatureTile(symbol: "text.book.closed.fill", title: "Disease Guide", selector: #selector(diseaseGuidePressed)),
            makeFeatureTile(symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", title: "Scan History", selector: #selector(historyPressed))
        ])
        topRow.axis = .horizontal
        topRow.spacing = 10
        topRow.distribution = .fillEqually

        let bottomRow = UIStackView(arrangedSubviews: [
            makeFeatureTile(symbol: "questionmark.bubble.fill", title: "How to Use", selector: #selector(howToUsePressed)),
            makeFeatureTile(symbol: "info.circle.fill", title: "About App", selector: #selector(aboutPressed))
        ])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 10
        bottomRow.distribution = .fillEqually

        featuresGrid.addArrangedSubview(topRow)
        featuresGrid.addArrangedSubview(bottomRow)
    }

    private func configureDisclaimer() {
        disclaimerLabel.translatesAutoresizingMaskIntoConstraints = false
        disclaimerLabel.text = "This app is for assistance only and does not replace expert diagnosis."
        disclaimerLabel.font = roundedFont(size: 11.5, weight: .regular)
        disclaimerLabel.textColor = UIColor(red: 0.25, green: 0.27, blue: 0.24, alpha: 0.9)
        disclaimerLabel.numberOfLines = 2
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.white.withAlphaComponent(0.98)
        bottomBar.layer.cornerRadius = 22
        bottomBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bottomBar.layer.shadowColor = UIColor.black.withAlphaComponent(0.10).cgColor
        bottomBar.layer.shadowOpacity = 1
        bottomBar.layer.shadowRadius = 10
        bottomBar.layer.shadowOffset = CGSize(width: 0, height: -4)

        let homeItem = makeBottomItem(symbol: "house.fill", title: "Home", active: true, selector: #selector(homePressed))
        let libraryItem = makeBottomItem(symbol: "book.closed.fill", title: "Library", active: false, selector: #selector(diseaseGuidePressed))
        let historyItem = makeBottomItem(symbol: "clock.fill", title: "History", active: false, selector: #selector(historyPressed))
        let aboutItem = makeBottomItem(symbol: "info.circle.fill", title: "About", active: false, selector: #selector(aboutPressed))

        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.tintColor = .white
        scanButton.setTitleColor(.white, for: .normal)
        scanButton.configuration = .plain()
        scanButton.configuration?.image = UIImage(systemName: "camera.fill")
        scanButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        scanButton.backgroundColor = UIColor(red: 0.43, green: 0.64, blue: 0.35, alpha: 1)
        scanButton.layer.cornerRadius = 28
        scanButton.layer.borderWidth = 4
        scanButton.layer.borderColor = UIColor(red: 0.87, green: 0.92, blue: 0.82, alpha: 1).cgColor
        scanButton.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        scanButton.layer.shadowOpacity = 1
        scanButton.layer.shadowRadius = 10
        scanButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        scanButton.addTarget(self, action: #selector(startScanningPressed), for: .touchUpInside)

        let navStack = UIStackView(arrangedSubviews: [homeItem, libraryItem, UIView(), historyItem, aboutItem])
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navStack.axis = .horizontal
        navStack.alignment = .top
        navStack.distribution = .fillEqually

        bottomBar.addSubview(navStack)
        bottomBar.addSubview(scanButton)

        NSLayoutConstraint.activate([
            navStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 16),
            navStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 8),
            navStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -8),
            navStack.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            scanButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            scanButton.centerYAnchor.constraint(equalTo: navStack.topAnchor, constant: 10),
            scanButton.widthAnchor.constraint(equalToConstant: 56),
            scanButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func buildLayout() {
        let heroWrapper = UIView()
        heroWrapper.translatesAutoresizingMaskIntoConstraints = false
        heroWrapper.addSubview(heroCard)
        heroWrapper.addSubview(actionCard)

        contentView.addSubview(headerIconView)
        contentView.addSubview(headerTitleLabel)
        contentView.addSubview(heroWrapper)
        contentView.addSubview(infoCard)
        contentView.addSubview(featuresGrid)
        contentView.addSubview(disclaimerLabel)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 90),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            headerIconView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 10),
            headerIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            headerIconView.widthAnchor.constraint(equalToConstant: 26),
            headerIconView.heightAnchor.constraint(equalToConstant: 26),

            headerTitleLabel.centerYAnchor.constraint(equalTo: headerIconView.centerYAnchor),
            headerTitleLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 10),
            headerTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            heroWrapper.topAnchor.constraint(equalTo: headerIconView.bottomAnchor, constant: 12),
            heroWrapper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            heroWrapper.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            heroCard.topAnchor.constraint(equalTo: heroWrapper.topAnchor),
            heroCard.leadingAnchor.constraint(equalTo: heroWrapper.leadingAnchor),
            heroCard.trailingAnchor.constraint(equalTo: heroWrapper.trailingAnchor),
            heroCard.heightAnchor.constraint(equalToConstant: 232),

            heroTextStack.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 22),
            heroTextStack.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 18),
            heroTextStack.widthAnchor.constraint(equalToConstant: 152),

            actionCard.topAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -18),
            actionCard.leadingAnchor.constraint(equalTo: heroWrapper.leadingAnchor),
            actionCard.trailingAnchor.constraint(equalTo: heroWrapper.trailingAnchor),
            actionCard.bottomAnchor.constraint(equalTo: heroWrapper.bottomAnchor),

            infoCard.topAnchor.constraint(equalTo: heroWrapper.bottomAnchor, constant: 12),
            infoCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            infoCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            featuresGrid.topAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: 8),
            featuresGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            featuresGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            disclaimerLabel.topAnchor.constraint(equalTo: featuresGrid.bottomAnchor, constant: 8),
            disclaimerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            disclaimerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            disclaimerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }

    private func configurePrimaryButton(_ button: UIButton, title: String, filled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = roundedFont(size: filled ? 16 : 14, weight: filled ? .semibold : .medium)
        button.layer.cornerRadius = filled ? 27 : 21
        button.layer.masksToBounds = true
        if filled {
            button.backgroundColor = UIColor(red: 0.39, green: 0.58, blue: 0.33, alpha: 1)
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = UIColor(red: 0.94, green: 0.93, blue: 0.92, alpha: 1)
            button.setTitleColor(UIColor(red: 0.16, green: 0.17, blue: 0.15, alpha: 1), for: .normal)
        }
    }

    private func makeFeatureTile(symbol: String, title: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        button.layer.cornerRadius = 20
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.06).cgColor
        button.layer.shadowOpacity = 1
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        button.heightAnchor.constraint(equalToConstant: 88).isActive = true
        button.accessibilityLabel = title
        button.addTarget(self, action: selector, for: .touchUpInside)

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.isUserInteractionEnabled = false
        iconWrap.backgroundColor = UIColor(red: 0.92, green: 0.92, blue: 0.84, alpha: 1)
        iconWrap.layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        icon.tintColor = UIColor(red: 0.39, green: 0.58, blue: 0.33, alpha: 1)
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        label.text = title
        label.font = roundedFont(size: 13.5, weight: .medium)
        label.textColor = UIColor(red: 0.18, green: 0.20, blue: 0.18, alpha: 1)
        label.numberOfLines = 2
        label.textAlignment = .center

        button.addSubview(iconWrap)
        iconWrap.addSubview(icon)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            iconWrap.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            iconWrap.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 44),
            iconWrap.heightAnchor.constraint(equalToConstant: 44),

            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10)
        ])

        return button
    }

    private func makeBottomItem(symbol: String, title: String, active: Bool, selector: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let tint = active
            ? UIColor(red: 0.39, green: 0.58, blue: 0.33, alpha: 1)
            : UIColor(red: 0.32, green: 0.34, blue: 0.31, alpha: 1)
        button.tintColor = tint
        button.accessibilityLabel = title
        button.configuration = .plain()
        button.configuration?.baseForegroundColor = tint
        button.configuration?.contentInsets = .zero

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        label.text = title
        label.font = roundedFont(size: 9.5, weight: active ? .semibold : .medium)
        label.textColor = tint
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.topAnchor.constraint(equalTo: button.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.widthAnchor.constraint(lessThanOrEqualTo: button.widthAnchor, constant: -4)
        ])
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    @objc private func startScanningPressed() {
        presentScanner(mode: .live)
    }

    @objc private func uploadImagePressed() {
        presentScanner(mode: .photo)
    }

    @objc private func homePressed() {
        scrollView.setContentOffset(.zero, animated: true)
    }

    @objc private func diseaseGuidePressed() {
        presentContent(DiseaseGuideViewController())
    }

    @objc private func historyPressed() {
        presentContent(ScanHistoryViewController())
    }

    @objc private func howToUsePressed() {
        presentContent(HowToUseViewController())
    }

    @objc private func aboutPressed() {
        presentContent(AboutAppViewController())
    }

    private func presentScanner(mode: CaptureMode) {
        let scanner = MainViewController(initialCaptureMode: mode, showsDismissButton: true)
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: true)
    }

    private func presentContent(_ viewController: UIViewController) {
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
}
