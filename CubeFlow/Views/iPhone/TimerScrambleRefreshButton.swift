#if os(iOS)
import SwiftUI
import UIKit

struct TimerScrambleRefreshButton: View {
    let action: () -> Void
    @AppStorage("appLanguage") private var languageCode = "en"
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TimerNativeScrambleRefreshButton(action: action,
                    label: appLocalizedString("timer.next_scramble", languageCode: languageCode)).fixedSize()
            } else {
                Button(action: action) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .compatibleGlassFromIOS16(in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .accessibilityLabel(Text("timer.next_scramble"))
        .accessibilityIdentifier("timer-next-scramble")
    }
}

@available(iOS 26.0, *)
private struct TimerNativeScrambleRefreshButton: UIViewRepresentable {
    let action: () -> Void
    let label: String
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 14, weight: .semibold)
        configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.accessibilityIdentifier = "timer-next-scramble"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.action?() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.accessibilityLabel = label
        button.isEnabled = isEnabled
        // UIKit owns press/release; scramble transactions must not reapply its configuration.
    }
    final class Coordinator { var action: (() -> Void)? }
}
#endif
