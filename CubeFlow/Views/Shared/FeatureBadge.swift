import SwiftUI

enum FeatureBadgeKind: CaseIterable {
    case new, beta

    var title: String {
        switch self {
        case .new: return "NEW"
        case .beta: return "BETA"
        }
    }

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .new: return "feature_badge.accessibility.new"
        case .beta: return "feature_badge.accessibility.beta"
        }
    }

    func palette(dark: Bool) -> (foreground: UInt32, background: UInt32) {
        switch (self, dark) {
        case (.new, false): return (0x005BC3, 0xE6F0FF)
        case (.new, true): return (0x82B5FF, 0x203650)
        case (.beta, false): return (0x6537B5, 0xEFE7FF)
        case (.beta, true): return (0xD3B4FF, 0x34264D)
        }
    }

    var glassTint: UInt32 {
        switch self {
        case .new: return 0x3D88EC
        case .beta: return 0x8B5CF6
        }
    }
}

struct FeatureBadge: View {
    let kind: FeatureBadgeKind
    var usesNativeGlass = true
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 12
    private let glassTintOpacity = 0.32

    var body: some View {
        surface.allowsHitTesting(false)
    }

    @ViewBuilder
    private var surface: some View {
        let palette = kind.palette(dark: colorScheme == .dark)
        let label = Text(verbatim: kind.title)
            .font(.system(size: fontSize, weight: .bold))
            .compatibleFontWidth(.expanded)
            .foregroundStyle(color(palette.foreground))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .fixedSize()
        if #available(iOS 26.0, macOS 26.0, *), usesNativeGlass {
            label.glassEffect(.regular.tint(color(kind.glassTint).opacity(glassTintOpacity)), in: .capsule)
        } else {
            label.background(color(palette.background), in: Capsule())
        }
    }

    private func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }
}

struct FeatureBadgeTitle: View {
    let title: Text
    let kind: FeatureBadgeKind?
    @Environment(\.dynamicTypeSize) private var typeSize

    var accessibilityTitle: Text {
        guard let kind else { return title }
        return Text("\(title), \(Text(kind.accessibilityKey))")
    }

    var body: some View {
        Group {
            if let kind {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) { title; badge(kind) }
                } else {
                    HStack(alignment: .center, spacing: 6) { title; badge(kind) }
                }
            } else {
                title
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private func badge(_ kind: FeatureBadgeKind) -> some View { FeatureBadge(kind: kind).accessibilityHidden(true) }
}
