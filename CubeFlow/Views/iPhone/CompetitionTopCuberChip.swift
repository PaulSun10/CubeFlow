import SwiftUI
import CoreText

/// Center the painted outline, not the font's advance and baseline box.
nonisolated struct CompetitionTopCuberEventInk: Shape {
    let glyph: String
    let fontName: String
    let pointSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let font = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        guard var character = glyph.utf16.first else { return Path() }
        var index = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &index, 1),
              let outline = CTFontCreatePathForGlyph(font, index, nil) else { return Path() }
        let ink = outline.boundingBoxOfPath
        return Path(outline).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
            tx: rect.midX - ink.midX, ty: rect.midY + ink.midY))
    }
}

/// The same intrinsic content is measured by the first-fit and visible flows.
struct CompetitionTopCuberChip: View {
    let preview: CompetitionTopCuberPreview
    let language: String
    let iconsReady: Bool
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 13
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        contents
            .font(.system(size: nameSize, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.065),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .competitionSizeDebug("chip", color: .red)
    }

    @ViewBuilder private var contents: some View {
        if #available(iOS 16.0, *) {
            CompetitionTopCuberChipLayout(spacing: 8) { name; badges }
        } else {
            HStack(alignment: .center, spacing: 8) { name; badges }
        }
    }

    private var name: some View {
        Text(preview.name).lineLimit(nil).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var badges: some View {
        ForEach(preview.badges) { badge in
            CompetitionTopCuberRecordBadge(badge: badge, language: language, iconsReady: iconsReady)
        }.fixedSize(horizontal: true, vertical: false)
    }
}

struct CompetitionTopCuberRecordBadge: View {
    let badge: CompetitionTopCuberBadge
    let language: String
    let iconsReady: Bool
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 25
    @ScaledMetric(relativeTo: .body) private var fallbackSize: CGFloat = 11

    private var color: Color {
        switch badge.tier {
        case .wr: return .red
        case .cr: return .orange
        case .nr: return .yellow
        }
    }
    private var eventName: String {
        CompetitionEventPresentation.localizedFullName(for: badge.eventID, languageCode: language)
    }
    var body: some View {
        surface
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(badge.tier.rawValue.uppercased()), \(eventName)")
    }
    @ViewBuilder private var surface: some View {
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular.tint(color.opacity(0.3)), in: Circle())
        } else {
            label.background(color.opacity(0.2), in: Circle())
        }
    }
    private var label: some View {
        Group {
            if iconsReady, CompetitionEventIconFont.ensureRegistered(),
               let glyph = CompetitionEventIconFont.glyph(for: badge.eventID) {
                CompetitionTopCuberEventInk(glyph: glyph,
                    fontName: CompetitionEventIconFont.fontName, pointSize: glyphSize).fill(color)
            } else {
                // Preserve the record tier and the full event accessibility label
                // without putting a long localized event name inside a circle.
                Text(badge.tier.rawValue.uppercased()).font(.system(size: fallbackSize, weight: .bold))
            }
        }.foregroundStyle(color).frame(width: diameter, height: diameter, alignment: .center)
    }
}
