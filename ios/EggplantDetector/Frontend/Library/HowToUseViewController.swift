import UIKit

final class HowToUseViewController: AppInfoBaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "How to Use"
        renderContent()
    }

    private func renderContent() {
        stackView.addArrangedSubview(makeCard(
            title: "1. Choose a scan mode",
            body: "Use Start Scanning for live analysis. Use Upload Image when you want to freeze one frame and review a steadier result.",
            iconName: "camera.fill"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "2. Select one leaf area",
            body: "Tap the preview to lock one eggplant leaf target. The app works best when one leaf fills the selected area.",
            iconName: "viewfinder"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "3. Wait for a confirmed result",
            body: "The app may ask for more light, less glare, or a clearer leaf. Save Summary appears only when the diagnosis is confirmed.",
            iconName: "checkmark.seal.fill"
        ))
        stackView.addArrangedSubview(makeCard(
            title: "4. Review history and guide",
            body: "Saved confirmed scans appear in Scan History. The Library explains only the supported labels in this model.",
            iconName: "book.closed.fill"
        ))
    }
}
