import SwiftUI
import UIKit

#if os(iOS)
struct CompetitionNavigationBarFontConfigurator: UIViewControllerRepresentable {
    let largeSubtitle: String

    func makeUIViewController(context: Context) -> CompetitionNavigationBarFontConfiguratorController {
        CompetitionNavigationBarFontConfiguratorController()
    }

    func updateUIViewController(_ uiViewController: CompetitionNavigationBarFontConfiguratorController, context: Context) {
        uiViewController.applyFontsIfNeeded(largeSubtitle: largeSubtitle)
    }
}

final class CompetitionNavigationBarFontConfiguratorController: UIViewController {
    func applyFontsIfNeeded(largeSubtitle: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let navigationController = self.resolvedNavigationController() else { return }
            let navigationBar = navigationController.navigationBar

            let largeTitleBase = UIFont.preferredFont(forTextStyle: .largeTitle)
            let largeTitleFont = UIFont.systemFont(ofSize: largeTitleBase.pointSize, weight: .bold)
            let inlineTitleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let inlineSubtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
            let largeSubtitleFont = UIFont.systemFont(ofSize: 15, weight: .medium)

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                standardAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                standardAppearance.largeSubtitleTextAttributes[.font] = largeSubtitleFont
                standardAppearance.largeSubtitleTextAttributes[.foregroundColor] = UIColor.secondaryLabel
            }

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy() ?? standardAppearance.copy()
            scrollEdgeAppearance.largeTitleTextAttributes[.font] = largeTitleFont
            scrollEdgeAppearance.titleTextAttributes[.font] = inlineTitleFont
            if #available(iOS 26.0, *) {
                scrollEdgeAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                scrollEdgeAppearance.largeSubtitleTextAttributes[.font] = largeSubtitleFont
                scrollEdgeAppearance.largeSubtitleTextAttributes[.foregroundColor] = UIColor.secondaryLabel
            }

            navigationBar.standardAppearance = standardAppearance
            navigationBar.compactAppearance = standardAppearance
            navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
            if #available(iOS 17.0, *) {
                navigationBar.compactScrollEdgeAppearance = scrollEdgeAppearance
            }

            guard let targetNavigationItem = self.resolvedNavigationItem(from: navigationController) else { return }

            if #available(iOS 16.0, *) {
                targetNavigationItem.style = .browser
            }
            if #available(iOS 26.0, *) {
                targetNavigationItem.subtitle = largeSubtitle
                targetNavigationItem.largeSubtitle = largeSubtitle
                targetNavigationItem.largeSubtitleView = CompetitionLargeSubtitleContainerView(
                    text: largeSubtitle,
                    topInset: 4
                )
            }
        }
    }

    private func resolvedNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var current: UIViewController? = parent
        while let controller = current {
            if let navigationController = controller.navigationController {
                return navigationController
            }
            current = controller.parent
        }

        return nil
    }

    private func resolvedNavigationItem(from navigationController: UINavigationController) -> UINavigationItem? {
        if let topItem = navigationController.topViewController?.navigationItem {
            return topItem
        }

        var current: UIViewController? = parent
        while let controller = current {
            let item = controller.navigationItem
            if item.title != nil {
                return item
            }
            if #available(iOS 26.0, *), item.subtitle != nil || item.largeSubtitle != nil {
                return item
            }
            current = controller.parent
        }

        return navigationController.visibleViewController?.navigationItem
    }
}

private final class CompetitionLargeSubtitleContainerView: UIView {
    private let label = UILabel()
    private let topInset: CGFloat

    init(text: String, topInset: CGFloat) {
        self.topInset = topInset
        super.init(frame: .zero)

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = text
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width, height: labelSize.height + topInset)
    }
}
#endif
