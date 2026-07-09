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
    private var lastAppliedLargeSubtitle: String?

    func applyFontsIfNeeded(largeSubtitle: String) {
        guard lastAppliedLargeSubtitle != largeSubtitle else { return }
        lastAppliedLargeSubtitle = largeSubtitle

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


struct CompetitionDetailNavigationBarConfigurator: UIViewControllerRepresentable {
    let title: String
    let subtitle: String
    let tabs: [CompetitionDetailTab]
    let languageCode: String
    @Binding var selection: CompetitionDetailTab

    func makeUIViewController(context: Context) -> CompetitionDetailNavigationBarConfiguratorController {
        CompetitionDetailNavigationBarConfiguratorController()
    }

    func updateUIViewController(_ uiViewController: CompetitionDetailNavigationBarConfiguratorController, context: Context) {
        uiViewController.apply(
            title: title,
            subtitle: subtitle,
            tabs: tabs,
            languageCode: languageCode,
            selection: $selection
        )
    }

    static func dismantleUIViewController(_ uiViewController: CompetitionDetailNavigationBarConfiguratorController, coordinator: ()) {
        uiViewController.clearLargeSubtitleView()
    }
}

final class CompetitionDetailNavigationBarConfiguratorController: UIViewController {
    private var subtitleContainer: CompetitionDetailLargeSubtitleContainerView?
    private var lastAppliedTitle: String?
    private var lastAppliedSubtitle: String?
    private var lastAppliedTabIDs: [String] = []

    func apply(
        title: String,
        subtitle: String,
        tabs: [CompetitionDetailTab],
        languageCode: String,
        selection: Binding<CompetitionDetailTab>
    ) {
        let tabIDs = tabs.map(\.rawValue)
        guard lastAppliedTitle != title ||
              lastAppliedSubtitle != subtitle ||
              lastAppliedTabIDs != tabIDs else {
            return
        }
        lastAppliedTitle = title
        lastAppliedSubtitle = subtitle
        lastAppliedTabIDs = tabIDs

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let navigationController = self.resolvedNavigationController(),
                  let targetNavigationItem = self.resolvedNavigationItem(from: navigationController) else { return }

            let navigationBar = navigationController.navigationBar
            let largeTitleBase = UIFont.preferredFont(forTextStyle: .largeTitle)
            let detailLargeTitleSize = self.fittedLargeTitleSize(for: title, baseSize: largeTitleBase.pointSize)
            let largeTitleFont = UIFont.systemFont(ofSize: detailLargeTitleSize, weight: .bold)
            let inlineTitleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let inlineSubtitleFont = UIFont.systemFont(ofSize: 13, weight: .medium)

            let standardAppearance = navigationBar.standardAppearance.copy()
            standardAppearance.titleTextAttributes[.font] = inlineTitleFont

            let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance?.copy() ?? standardAppearance.copy()
            scrollEdgeAppearance.largeTitleTextAttributes[.font] = largeTitleFont
            scrollEdgeAppearance.titleTextAttributes[.font] = inlineTitleFont

            if #available(iOS 26.0, *) {
                standardAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                scrollEdgeAppearance.subtitleTextAttributes[.font] = inlineSubtitleFont
                targetNavigationItem.largeTitle = title
                targetNavigationItem.subtitle = subtitle
                targetNavigationItem.largeSubtitle = subtitle

                let container = self.subtitleContainer ?? CompetitionDetailLargeSubtitleContainerView()
                container.update(
                    subtitle: subtitle,
                    tabs: tabs,
                    languageCode: languageCode,
                    selection: selection
                )
                self.subtitleContainer = container
                targetNavigationItem.largeSubtitleView = container
            }

            navigationBar.standardAppearance = standardAppearance
            navigationBar.compactAppearance = standardAppearance
            navigationBar.scrollEdgeAppearance = scrollEdgeAppearance
            if #available(iOS 17.0, *) {
                navigationBar.compactScrollEdgeAppearance = scrollEdgeAppearance
            }
        }
    }

    private func fittedLargeTitleSize(for title: String, baseSize: CGFloat) -> CGFloat {
        let maximumSize = min(baseSize, 30)
        let minimumSize: CGFloat = 22
        let availableWidth = max(UIScreen.main.bounds.width - 56, 220)
        var candidate = maximumSize

        while candidate > minimumSize {
            let font = UIFont.systemFont(ofSize: candidate, weight: .bold)
            let measuredWidth = (title as NSString).size(withAttributes: [.font: font]).width
            if measuredWidth <= availableWidth {
                break
            }
            candidate -= 1
        }

        return max(candidate, minimumSize)
    }

    func clearLargeSubtitleView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let navigationController = self.resolvedNavigationController(),
                  let targetNavigationItem = self.resolvedNavigationItem(from: navigationController) else { return }
            if #available(iOS 26.0, *) {
                targetNavigationItem.largeSubtitleView = nil
                targetNavigationItem.largeSubtitle = nil
                targetNavigationItem.subtitle = nil
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

        return navigationController.visibleViewController?.navigationItem
    }
}

private struct CompetitionDetailLargeSubtitleContent: View {
    let subtitle: String
    let tabs: [CompetitionDetailTab]
    let languageCode: String
    @Binding var selection: CompetitionDetailTab

    var body: some View {
        VStack(spacing: 8) {
            Text(subtitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            CompetitionDetailTabStrip(
                tabs: tabs,
                languageCode: languageCode,
                selection: $selection
            )
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private final class CompetitionDetailLargeSubtitleContainerView: UIView {
    private var hostingController: UIHostingController<CompetitionDetailLargeSubtitleContent>?

    func update(
        subtitle: String,
        tabs: [CompetitionDetailTab],
        languageCode: String,
        selection: Binding<CompetitionDetailTab>
    ) {
        let rootView = CompetitionDetailLargeSubtitleContent(
            subtitle: subtitle,
            tabs: tabs,
            languageCode: languageCode,
            selection: selection
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.hostingController = hostingController
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let targetWidth = max(UIScreen.main.bounds.width - 32, 260)
        guard let hostingView = hostingController?.view else {
            return CGSize(width: targetWidth, height: 68)
        }

        let fittingSize = hostingView.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: targetWidth, height: max(fittingSize.height, 68))
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
