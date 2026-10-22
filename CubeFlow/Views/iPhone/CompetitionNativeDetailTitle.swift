import SwiftUI
import UIKit

/// Reuse CubeFlow's original large-title fitting without its inline font override.
struct CompetitionNativeDetailTitle: UIViewControllerRepresentable {
    var title: String = ""
    var inlineOpacity: CGFloat? = nil
    func makeUIViewController(context: Context) -> CompetitionNativeDetailTitleController {
        CompetitionNativeDetailTitleController()
    }
    func updateUIViewController(_ controller: CompetitionNativeDetailTitleController, context: Context) {
        controller.titleText = title
        controller.inlineOpacity = inlineOpacity
        controller.applyIfNeeded()
    }
}

final class CompetitionNativeDetailTitleController: UIViewController {
    private var saved: [UINavigationBarAppearance?]?
    var titleText = ""
    var inlineOpacity: CGFloat?
    private var appliedOpacity: CGFloat?
    private var appliedTitle = ""
    private var appliedWidth: CGFloat = 0
    private var appliedCategory: UIContentSizeCategory?

    static func nativeAppearance(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
        let native = appearance.copy()
        native.titleTextAttributes.removeValue(forKey: .font)
        native.largeTitleTextAttributes.removeValue(forKey: .font)
        return native
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard saved == nil, let bar = navigationController?.navigationBar else { return }
        saved = [bar.standardAppearance, bar.compactAppearance, bar.scrollEdgeAppearance]
        if #available(iOS 15.0, *) {
            saved?.append(bar.compactScrollEdgeAppearance)
        }
        applyIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyIfNeeded()
    }

    func applyIfNeeded() {
        guard let saved, let bar = navigationController?.navigationBar, bar.bounds.width > 0 else { return }
        let width = bar.bounds.width - bar.safeAreaInsets.left - bar.safeAreaInsets.right - 32
        let category = bar.traitCollection.preferredContentSizeCategory
        guard appliedTitle != titleText || appliedWidth != width || appliedCategory != category || appliedOpacity != inlineOpacity else { return }
        appliedTitle = titleText; appliedWidth = width; appliedCategory = category
        appliedOpacity = inlineOpacity
        let base = UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: bar.traitCollection)
        let size = CompetitionDetailNavigationBarConfiguratorController.fittedLargeTitleSize(
            for: titleText, baseSize: base.pointSize)
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        func appearance(_ source: UINavigationBarAppearance) -> UINavigationBarAppearance {
            let result = Self.nativeAppearance(source)
            if let inlineOpacity = self.inlineOpacity {
                // The restored in-content title drives only visibility. UIKit owns inline font/layout.
                result.titleTextAttributes[.foregroundColor] = UIColor { traits in
                    UIColor.label.resolvedColor(with: traits).withAlphaComponent(inlineOpacity)
                }
            } else {
                result.largeTitleTextAttributes[.font] = font
            }
            return result
        }
        if let standard = saved[0] { bar.standardAppearance = appearance(standard) }
        if let compact = saved[1] { bar.compactAppearance = appearance(compact) }
        bar.scrollEdgeAppearance = appearance(saved[2] ?? saved[0]!)
        if #available(iOS 15.0, *), saved.count > 3, let compactEdge = saved[3] {
            bar.compactScrollEdgeAppearance = appearance(compactEdge)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let saved, let bar = navigationController?.navigationBar else { return }
        if let standard = saved[0] { bar.standardAppearance = standard }
        bar.compactAppearance = saved[1]
        bar.scrollEdgeAppearance = saved[2]
        if #available(iOS 15.0, *), saved.count > 3 { bar.compactScrollEdgeAppearance = saved[3] }
        self.saved = nil
        appliedWidth = 0
    }
}
