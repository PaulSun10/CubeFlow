#if os(iOS)
import SwiftUI

struct SolveRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SolveRangeControlFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct SolveMoveRequest: Identifiable {
    let id = UUID()
    let sourceID: UUID
    let solveIDs: Set<UUID>
}

struct SolveMoveDestinationView: View {
    let sessions: [Session]
    let request: SolveMoveRequest
    let languageCode: String
    let move: (Session) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var destination: Session?

    var body: some View {
        CompatibleNavigationContainer {
            List {
                    ForEach(sessions) { session in
                        Button { destination = session } label: {
                            HStack {
                                Text(session.name).font(.body.weight(.medium))
                                    .foregroundStyle(session.id == request.sourceID ? .secondary : .primary)
                                Spacer()
                                Text(NumeralPresentation.formatLocalizedInteger(session.solveCount,
                                    template: appLocalizedString("common.solves_format", languageCode: languageCode)))
                                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(session.id == request.sourceID)
                    }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(solveMoveLabel(count: request.solveIDs.count, languageCode: languageCode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("common.cancel"))
                }
            }
            .alert(solveMoveLabel(count: request.solveIDs.count, languageCode: languageCode), isPresented: Binding(
                get: { destination != nil }, set: { if !$0 { destination = nil } }
            ), presenting: destination) { session in
                Button("data.move.action") {
                    do { try move(session); dismiss() } catch { failed = true }
                }
                Button("common.cancel", role: .cancel) {}
            } message: { session in
                Text(String(format: appLocalizedString("data.move.confirm", languageCode: languageCode), session.name))
            }
            .alert("data.move.failed", isPresented: $failed) { Button("common.done", role: .cancel) {} }
        }
    }
}

struct SolveSelectionCheckmark: View {
    let selected: Bool
    var size: CGFloat = 24
    var weight: Font.Weight = .regular
    var replacementAnimation: Animation = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var symbol: String { selected ? "checkmark.circle.fill" : "circle" }

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *), !reduceMotion {
            image.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                .animation(replacementAnimation, value: selected)
        } else if #available(iOS 17.0, *), !reduceMotion {
            image.contentTransition(.symbolEffect(.replace)).animation(replacementAnimation, value: selected)
        } else {
            image
        }
    }
    private var image: some View {
        Image(systemName: symbol).font(.system(size: size, weight: weight))
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct DataTabBarVisibility: ViewModifier {
    let hidden: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.compatibleTabBarVisibility(hidden: hidden)
        } else {
            content.background { DataTabBarControllerBridge(hidden: hidden).frame(width: 0, height: 0) }
        }
    }
}

/// iOS 15 does not have the SwiftUI toolbar visibility preference.
private struct DataTabBarControllerBridge: UIViewControllerRepresentable {
    let hidden: Bool
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hidden = hidden
        controller.apply()
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }
    final class Controller: UIViewController {
        var hidden = false
        private weak var owner: UITabBarController?
        private var originalHidden = false
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        func apply() {
            guard let tab = tabBarController else { return }
            if owner !== tab { restore() }
            if hidden {
                if owner == nil {
                    owner = tab
                    originalHidden = tab.tabBar.isHidden
                }
                setHidden(true, on: tab)
            } else if owner === tab {
                setHidden(originalHidden, on: tab)
                owner = nil
            }
        }
        private func setHidden(_ hidden: Bool, on tab: UITabBarController) {
            if tab.tabBar.isHidden != hidden {
                tab.tabBar.isHidden = hidden
                tab.view.setNeedsLayout()
            }
        }
        func restore() {
            if let owner { setHidden(originalHidden, on: owner) }
            owner = nil
        }
    }
}
#endif
