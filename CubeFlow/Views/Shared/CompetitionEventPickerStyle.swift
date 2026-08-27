import SwiftUI

private struct CompetitionPickerBlurReplicaKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var competitionPickerBlurReplica: Bool {
        get { self[CompetitionPickerBlurReplicaKey.self] }
        set { self[CompetitionPickerBlurReplicaKey.self] = newValue }
    }
}

private struct CompetitionPickerContentOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CompetitionEventPickerCapsuleStyle: ViewModifier {
    let isSelected: Bool
    @Environment(\.competitionPickerBlurReplica) private var isBlurReplica

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .horizontalCapsuleSelectorSurface(
                isSelected: isSelected,
                legacySelectedForeground: .white,
                legacyUnselectedForeground: .white
            ) {
                Group {
                    if isSelected {
                        Capsule().fill(Color.blue)
                    } else if isBlurReplica {
                        Capsule().fill(Color(uiColor: .secondarySystemFill))
                    } else {
                        Capsule().fill(.thinMaterial)
                    }
                }
            }
    }
}

extension View {
    func competitionEventPickerCapsule(isSelected: Bool) -> some View {
        modifier(CompetitionEventPickerCapsuleStyle(isSelected: isSelected))
    }
}

struct CompetitionProgressiveBlurScrollView<Content: View>: View {
    private let content: Content
    private let coordinateSpaceName = UUID()
    private let leadingOverlap: CGFloat = 8
    private let blurWidth: CGFloat = 22
    @State private var scrollOffset: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
            .scrollEdgeEffectStyle(.soft, for: .leading)
            .clipped()
        } else {
            legacyBlurScrollView
        }
    }

    private var legacyBlurScrollView: some View {
        ZStack(alignment: .leading) {
            trackedScrollView

            if scrollOffset > 0 {
                ZStack(alignment: .leading) {
                    Color(uiColor: .systemGroupedBackground)
                        .opacity(0.12)

                    content
                        .environment(\.competitionPickerBlurReplica, true)
                        .fixedSize(horizontal: true, vertical: true)
                        .offset(x: -scrollOffset + leadingOverlap)
                        .blur(radius: 1.2)
                        .opacity(0.55)
                }
                .frame(width: blurWidth, alignment: .leading)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.62), location: 0),
                            .init(color: .black.opacity(0.4), location: 0.35),
                            .init(color: .black.opacity(0.15), location: 0.75),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(min(scrollOffset / 6, 1))
                .offset(x: -leadingOverlap)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var trackedScrollView: some View {
        if #available(iOS 18.0, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
            .clipped()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(geometry.contentOffset.x + geometry.contentInsets.leading, 0)
            } action: { _, newOffset in
                scrollOffset = newOffset
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                content
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: CompetitionPickerContentOffsetKey.self,
                                value: proxy.frame(in: .named(coordinateSpaceName)).minX
                            )
                        }
                    }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .clipped()
            .onPreferenceChange(CompetitionPickerContentOffsetKey.self) { minX in
                scrollOffset = max(-minX, 0)
            }
        }
    }
}
