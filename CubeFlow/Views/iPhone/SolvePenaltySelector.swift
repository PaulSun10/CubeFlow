#if os(iOS)
import SwiftUI
import UIKit

/// One native stack gives every capsule the tallest localized button's height,
/// including when only one title wraps. Reuse Sessions' native action policy.
struct SolvePenaltySelector: UIViewRepresentable {
    let selected: SolveResult
    let language: String
    let select: (SolveResult) -> Void

    func makeUIView(context: Context) -> PenaltyStack { PenaltyStack() }
    func updateUIView(_ stack: PenaltyStack, context: Context) {
        stack.select = select
        for (index, result) in PenaltyStack.choices.enumerated() {
            let button = stack.arrangedSubviews[index] as! UIButton
            let tint: UIColor? = selected == result ? .systemBlue : nil
            var config = SessionNativeActionStyle.configuration(tint: tint)
            config.title = appLocalizedString(["solve.penalty.none", "+2", "common.dnf"][index], languageCode: language)
            config.buttonSize = .large; config.cornerStyle = .capsule
            config.titleLineBreakMode = .byWordWrapping
            button.configuration = config
            button.titleLabel?.numberOfLines = 0
            button.tintColor = tint
            button.accessibilityTraits = selected == result ? [.button, .selected] : [.button]
        }
        stack.invalidateIntrinsicContentSize()
    }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PenaltyStack, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    final class PenaltyStack: UIStackView {
        static let choices: [SolveResult] = [.solved, .plusTwo, .dnf]
        var select: ((SolveResult) -> Void)?
        private var measuredWidth: CGFloat = 0
        init() {
            super.init(frame: .zero)
            axis = .horizontal; spacing = 10; distribution = .fillEqually; alignment = .fill
            for result in Self.choices {
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = "solve-penalty-\(result.rawValue)"
                button.addAction(UIAction { [weak self] _ in self?.select?(result) }, for: .touchUpInside)
                addArrangedSubview(button)
            }
        }
        required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func sizeThatFits(_ size: CGSize) -> CGSize {
            let width = max(0, (size.width - spacing * 2) / 3)
            let height = arrangedSubviews.map { $0.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height }.max() ?? 0
            return CGSize(width: size.width, height: max(44, height))
        }
        override var intrinsicContentSize: CGSize {
            let height = bounds.width > 0 ? sizeThatFits(bounds.size).height
                : max(44, arrangedSubviews.map { $0.intrinsicContentSize.height }.max() ?? 0)
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if measuredWidth != bounds.width { measuredWidth = bounds.width; invalidateIntrinsicContentSize() }
        }
    }
}
#endif
