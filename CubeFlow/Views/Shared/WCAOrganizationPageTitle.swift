import SwiftUI

private struct ScrollAwareTitleCoordinateSpaceKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private extension EnvironmentValues {
    var scrollAwareTitleCoordinateSpace: UUID? {
        get { self[ScrollAwareTitleCoordinateSpaceKey.self] }
        set { self[ScrollAwareTitleCoordinateSpaceKey.self] = newValue }
    }
}

private struct ScrollAwareContentTitleMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let nextValue = nextValue() {
            value = nextValue
        }
    }
}

/// Marks the in-content title whose visibility controls a matching inline navigation title.
struct ScrollAwareContentTitle: View {
    let title: String

    @Environment(\.scrollAwareTitleCoordinateSpace) private var coordinateSpace

    var body: some View {
        Text(title)
            .background {
                if let coordinateSpace {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollAwareContentTitleMaxYKey.self,
                            value: proxy.frame(in: .named(coordinateSpace)).maxY
                        )
                    }
                }
            }
    }
}

private struct ScrollAwareNavigationTitleModifier: ViewModifier {
    let title: String
    let isEnabled: Bool

    @State private var coordinateSpace = UUID()
    @State private var showsInlineTitle = false

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: coordinateSpace)
            .environment(\.scrollAwareTitleCoordinateSpace, isEnabled ? coordinateSpace : nil)
            .onPreferenceChange(ScrollAwareContentTitleMaxYKey.self) { titleMaxY in
                updateInlineTitleVisibility(titleMaxY: titleMaxY)
            }
            .onChange(of: title) { _ in
                showsInlineTitle = false
            }
            .onChange(of: isEnabled) { enabled in
                if !enabled { showsInlineTitle = false }
            }
            .navigationTitle(isEnabled ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isEnabled {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .opacity(showsInlineTitle ? 1 : 0)
                            .offset(y: showsInlineTitle ? 0 : 1.5)
                            .animation(.easeInOut(duration: 0.18), value: showsInlineTitle)
                            .accessibilityHidden(!showsInlineTitle)
                            .allowsHitTesting(false)
                    }
                }
            }
    }

    private func updateInlineTitleVisibility(titleMaxY: CGFloat?) {
        guard isEnabled else {
            if showsInlineTitle { showsInlineTitle = false }
            return
        }
        // A List may recycle its title row after it leaves the viewport. Preserve the last
        // resolved state until the marker is visible again instead of treating that as "at top".
        guard let titleMaxY else { return }

        // Separate enter/exit thresholds prevent tiny scroll bounces from flickering the title.
        let shouldShow = showsInlineTitle ? titleMaxY < 4 : titleMaxY <= -2
        guard shouldShow != showsInlineTitle else { return }
        showsInlineTitle = shouldShow
    }
}

private struct ExternallyControlledScrollAwareNavigationTitleModifier: ViewModifier {
    let title: String
    let showsInlineTitle: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .opacity(showsInlineTitle ? 1 : 0)
                        .offset(y: showsInlineTitle ? 0 : 1.5)
                        .animation(.easeInOut(duration: 0.18), value: showsInlineTitle)
                        .accessibilityHidden(!showsInlineTitle)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Uses the navigation title only after an identical in-content title leaves the viewport.
    func scrollAwareNavigationTitle(_ title: String, isEnabled: Bool = true) -> some View {
        modifier(ScrollAwareNavigationTitleModifier(title: title, isEnabled: isEnabled))
    }

    /// Uses an external scroll container's visibility signal with the shared inline-title style.
    func scrollAwareNavigationTitle(_ title: String, showsInlineTitle: Bool) -> some View {
        modifier(
            ExternallyControlledScrollAwareNavigationTitleModifier(
                title: title,
                showsInlineTitle: showsInlineTitle
            )
        )
    }
}

struct WCAOrganizationPageTitle: View {
    let title: String

    var body: some View {
        ScrollAwareContentTitle(title: title)
            .font(.system(size: 28, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
    }
}
