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

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

/// iOS 15 fallback only; newer systems use SwiftUI's native tab-bar visibility.
struct DataLegacyTabBarVisibility: UIViewControllerRepresentable {
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
            if owner == nil { owner = tab; originalHidden = tab.tabBar.isHidden }
            tab.tabBar.isHidden = hidden
            tab.view.setNeedsLayout()
        }
        func restore() { owner?.tabBar.isHidden = originalHidden; owner?.view.setNeedsLayout() }
    }
}
#endif
