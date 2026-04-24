import SwiftUI

struct CompatibleNavigationContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
        }
    }
}

extension View {
    @ViewBuilder
    func compatibleGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func compatibleGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive())
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    func compatibleTintedGlass<S: Shape>(_ tint: Color, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(tint.opacity(0.28), in: shape)
        }
    }

    @ViewBuilder
    func compatibleGlassFromIOS16<S: Shape>(in shape: S) -> some View {
        if #available(iOS 16.0, *) {
            self.compatibleGlass(in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTintedGlassFromIOS16<S: Shape>(_ tint: Color, in shape: S) -> some View {
        if #available(iOS 16.0, *) {
            self.compatibleTintedGlass(tint, in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleProminentButtonFromIOS16(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(tint.opacity(0.8))
        } else if #available(iOS 16.0, *) {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(tint)
        } else {
            self.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func compatibleLargeSheet() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleMediumLargeSheet() -> some View {
        if #available(iOS 16.0, *) {
            self
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleMediumSheet() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium])
        } else {
            self
        }
    }

    @ViewBuilder
    func compatiblePopoverCompactAdaptation() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationCompactAdaptation(.popover)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleClearPresentationBackground() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(.clear)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleMenuActionDismissBehaviorDisabled() -> some View {
        if #available(iOS 16.4, *) {
            self.menuActionDismissBehavior(.disabled)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleListSectionSpacing(_ spacing: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(spacing)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleNavigationDestination<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.sheet(item: item) { value in
                CompatibleNavigationContainer {
                    destination(value)
                }
            }
        }
    }

    @ViewBuilder
    func compatibleNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            self.sheet(isPresented: isPresented) {
                CompatibleNavigationContainer {
                    destination()
                }
            }
        }
    }

    @ViewBuilder
    func compatibleNavigationSubtitle(_ subtitle: Text) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleNumericTextTransition() -> some View {
        if #available(iOS 16.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleFontWidth(_ option: TimerFontDesignOption) -> some View {
        if #available(iOS 16.0, *) {
            switch option {
            case .expanded:
                self.fontWidth(.expanded)
            case .compressed:
                self.fontWidth(.compressed)
            case .condensed:
                self.fontWidth(.condensed)
            case .default, .monospaced, .rounded, .serif:
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTabBarBackground() -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTabBarHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTabBarVisibility(hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(hidden ? .hidden : .visible, for: .tabBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleNavigationBarHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .navigationBar)
        } else {
            self.navigationBarHidden(true)
        }
    }
}
