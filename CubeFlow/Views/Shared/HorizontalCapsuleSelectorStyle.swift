import SwiftUI

struct HorizontalCapsuleSelectorGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

enum HorizontalCapsuleSelectorLayout {
    // Interactive glass grows slightly outside its resting capsule bounds.
    static let interactionOverflow: CGFloat = 3
    static let compactContainerHeight: CGFloat = 36 + interactionOverflow * 2
}

struct HorizontalCapsuleSelectionIndicator<LegacyContent: View>: View {
    private let tint: Color?
    private let legacyContent: LegacyContent

    init(tint: Color? = nil, @ViewBuilder legacyContent: () -> LegacyContent) {
        self.tint = tint
        self.legacyContent = legacyContent()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            if let tint {
                Color.clear
                    .glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                Color.clear
                    .glassEffect(.regular, in: .capsule)
            }
        } else {
            legacyContent
        }
    }
}

extension View {
    @ViewBuilder
    func horizontalCapsuleSelectorSurface<LegacyBackground: View>(
        isSelected: Bool,
        isEnabled: Bool = true,
        selectedTint: Color = .blue,
        legacySelectedForeground: Color = .white,
        legacyUnselectedForeground: Color = .primary,
        @ViewBuilder legacyBackground: () -> LegacyBackground
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .opacity(isEnabled ? 1 : 0.55)
                .glassEffect(
                    isSelected
                        ? .regular.tint(selectedTint).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
                .padding(.vertical, HorizontalCapsuleSelectorLayout.interactionOverflow)
                .animation(.snappy(duration: 0.22, extraBounce: 0), value: isSelected)
        } else {
            self
                .foregroundStyle(isSelected ? legacySelectedForeground : legacyUnselectedForeground)
                .background(legacyBackground())
        }
    }

    @ViewBuilder
    func legacyHorizontalSelectorMaterial<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func legacyHorizontalSelectorShadow(
        color: Color,
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
}

enum HorizontalCapsuleSelectorForeground {
    static func color(
        isSelected: Bool,
        legacySelected: Color = .white,
        legacyUnselected: Color = .primary
    ) -> Color {
        if #available(iOS 26.0, *) {
            return isSelected ? .white : .primary
        }
        return isSelected ? legacySelected : legacyUnselected
    }
}
