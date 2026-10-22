#if os(iOS)
import SwiftUI
import UIKit

/// The Data > Sessions Edit/Done reference is UIKit's prominent bar button,
/// with only its system tint configured. Keep this policy shared, not a second
/// tinted-background/foreground recipe in the management card.
enum SessionNativeActionStyle {
    static func apply(to item: UIBarButtonItem, tint: UIColor) {
        item.tintColor = tint
        if #available(iOS 26.0, *) { item.style = .prominent }
        else { item.style = .done }
    }

    static func configuration(tint: UIColor?) -> UIButton.Configuration {
        if #available(iOS 26.0, *) { return tint == nil ? .glass() : .prominentGlass() }
        return tint == nil ? .bordered() : .borderedProminent()
    }
}

/// UIBarButtonItem remains content-sized in a toolbar even when its public
/// width is set. Use UIKit's corresponding native prominent Glass button for
/// full-width card actions; no custom backgrounds or foreground overrides.
struct SmartCubeNativeAction: UIViewRepresentable {
    let title: String
    let tint: UIColor?
    let enabled: Bool
    let identifier: String
    let perform: () -> Void
    var isLarge = false

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.perform?() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.perform = perform
        var config = SessionNativeActionStyle.configuration(tint: tint)
        config.title = title
        if isLarge { config.buttonSize = .large }
        if button.configuration != config { button.configuration = config }
        button.tintColor = tint
        button.isEnabled = enabled
        button.accessibilityIdentifier = identifier
    }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
    final class Coordinator {
        var perform: (() -> Void)?
    }
}
#endif
