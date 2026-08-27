import Foundation
import UIKit
import CoreText
import SwiftUI

enum CompetitionEventPresentation {
    private static let officialNames: [String: String] = [
        "222": "2x2x2 Cube",
        "333": "3x3x3 Cube",
        "444": "4x4x4 Cube",
        "555": "5x5x5 Cube",
        "666": "6x6x6 Cube",
        "777": "7x7x7 Cube",
        "333bf": "3x3x3 Blindfolded",
        "333fm": "3x3x3 Fewest Moves",
        "333oh": "3x3x3 One-Handed",
        "clock": "Clock",
        "minx": "Megaminx",
        "pyram": "Pyraminx",
        "skewb": "Skewb",
        "sq1": "Square-1",
        "444bf": "4x4x4 Blindfolded",
        "555bf": "5x5x5 Blindfolded",
        "333mbf": "3x3x3 Multi-Blind",
        "fto": "Face Turning Octahedron",
        "333ft": "3x3x3 With Feet",
        "magic": "Magic",
        "mmagic": "Master Magic",
        "333mbo": "3x3x3 Multi-Blind Old Style",
        "333relay": "3x3x3 Relay",
        "redi": "Redi Cube",
        "kilominx": "Kilominx",
        "mirror": "Mirror Blocks",
        "ivy": "Ivy Cube"
    ]

    private static let localizationKeys: [String: String] = [
        "222": "event.2x2",
        "333": "event.3x3",
        "444": "event.4x4",
        "555": "event.5x5",
        "666": "event.6x6",
        "777": "event.7x7",
        "333bf": "event.3x3bld",
        "333fm": "event.3x3fm",
        "333oh": "event.3x3oh",
        "clock": "event.clock",
        "minx": "event.megaminx",
        "pyram": "event.pyraminx",
        "skewb": "event.skewb",
        "sq1": "event.square1",
        "444bf": "event.4x4bld",
        "555bf": "event.5x5bld",
        "333mbf": "event.3x3mbld"
    ]

    static func officialName(for eventID: String, fallback: String? = nil) -> String {
        let canonicalID = canonicalEventID(eventID)
        return officialNames[canonicalID] ?? cleanedFallback(fallback, eventID: eventID)
    }

    static func localizedFullName(
        for eventID: String,
        languageCode: String,
        fallback: String? = nil
    ) -> String {
        let canonicalID = canonicalEventID(eventID)
        let official = officialNames[canonicalID]

        if languageCode.lowercased().hasPrefix("en"), let official {
            return official
        }

        if let key = localizationKeys[canonicalID] {
            let localized = appLocalizedString(
                key,
                languageCode: languageCode,
                defaultValue: official ?? cleanedFallback(fallback, eventID: eventID)
            )
            return expandingCommonAbbreviations(in: localized)
        }

        if let official {
            return official
        }

        let fallbackName = cleanedFallback(fallback, eventID: eventID)
        return normalizedKnownCapitalization(fallbackName, canonicalID: canonicalID)
    }

    static func normalizedName(
        for eventID: String,
        fallback: String?,
        languageCode: String
    ) -> String {
        let canonicalID = canonicalEventID(eventID)
        let fallbackName = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedFallback = fallbackName
            .replacingOccurrences(of: "×", with: "x")
            .lowercased()

        if fallbackName.isEmpty
            || normalizedFallback == eventID.lowercased()
            || containsCommonAbbreviation(fallbackName)
            || (fallbackName == fallbackName.uppercased() && officialNames[canonicalID] != nil) {
            return localizedFullName(for: canonicalID, languageCode: languageCode, fallback: fallback)
        }

        return normalizedKnownCapitalization(fallbackName, canonicalID: canonicalID)
    }

    private static func canonicalEventID(_ eventID: String) -> String {
        let raw = eventID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activityID = raw.components(separatedBy: "-r").first ?? raw
        switch activityID {
        case "333bld": return "333bf"
        case "444bld": return "444bf"
        case "555bld": return "555bf"
        case "333mbld": return "333mbf"
        default: return activityID
        }
    }

    private static func cleanedFallback(_ fallback: String?, eventID: String) -> String {
        let value = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? eventID : expandingCommonAbbreviations(in: value)
    }

    private static func containsCommonAbbreviation(_ value: String) -> Bool {
        value.range(
            of: #"(?i)(?:^|[\s-])(OH|BLD|FMC|MBLD)(?:$|[\s-])"#,
            options: .regularExpression
        ) != nil
    }

    private static func expandingCommonAbbreviations(in value: String) -> String {
        let replacements = [
            (#"(?i)\bMBLD\b"#, "Multi-Blind"),
            (#"(?i)\bFMC\b"#, "Fewest Moves"),
            (#"(?i)\bBLD\b"#, "Blindfolded"),
            (#"(?i)\bOH\b"#, "One-Handed")
        ]
        return replacements.reduce(value) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }
    }

    private static func normalizedKnownCapitalization(_ value: String, canonicalID: String) -> String {
        switch canonicalID {
        case "clock": return "Clock"
        case "skewb": return "Skewb"
        default: return expandingCommonAbbreviations(in: value)
        }
    }
}

struct CompetitionEventGlyph: View {
    let glyph: String
    let eventName: String
    var size: CGFloat = 15
    var color: Color = .primary

    var body: some View {
        Text(glyph)
            .font(.custom(CompetitionEventIconFont.fontName, size: size))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 2)
            .frame(minHeight: size + 6, alignment: .center)
            .accessibilityLabel(eventName)
    }
}

enum CompetitionEventIconFont {
    static let fontName = "event-icon"
    static let leadingOpticalInset: CGFloat = 1.5

    struct GlyphMetrics {
        let bounds: CGRect
        let advance: CGFloat

        var centerOffset: CGFloat {
            bounds.midX - advance / 2
        }
    }

    private static let glyphs: [String: String] = [
        "333": "\u{e900}",
        "222": "\u{e901}",
        "444": "\u{e902}",
        "555": "\u{e903}",
        "666": "\u{e904}",
        "777": "\u{e905}",
        "333bf": "\u{e906}",
        "333bld": "\u{e906}",
        "333bfcheck": "\u{e906}",
        "333fm": "\u{e907}",
        "333oh": "\u{e908}",
        "333ft": "\u{e909}",
        "minx": "\u{e90a}",
        "pyram": "\u{e90b}",
        "clock": "\u{e90c}",
        "skewb": "\u{e90d}",
        "sq1": "\u{e90e}",
        "444bf": "\u{e90f}",
        "444bld": "\u{e90f}",
        "444bfcheck": "\u{e90f}",
        "555bf": "\u{e910}",
        "555bld": "\u{e910}",
        "555bfcheck": "\u{e910}",
        "333mbf": "\u{e911}",
        "333mbld": "\u{e911}",
        "333mbo": "\u{e911}",
        "submission": "\u{e911}",
        "magic": "\u{e912}",
        "mmagic": "\u{e913}",
        "stack": "\u{e914}",
        "registration": "\u{e915}",
        "intro": "\u{e916}",
        "break": "\u{e917}",
        "lunch": "\u{e918}",
        "ceremony": "\u{e919}",
        "lucky": "\u{e91a}",
        "funny": "\u{e91b}",
        "333relay": "\u{e91c}",
        "redi": "\u{e91d}",
        "kilominx": "\u{e91e}",
        "mirror": "\u{e91f}",
        "ivy": "\u{e920}",
        "fto": "\u{e921}"
    ]

    // These aliases only resolve to glyphs that are present in event-icon.ttf.
    // Keep unknown custom events unmapped so the UI never shows a placeholder icon.
    private static let aliases: [(name: String, eventID: String)] = [
        ("3x3x3 multi blind old style", "333mbo"),
        ("3x3 multi blind old style", "333mbo"),
        ("3x3x3 blindfolded", "333bf"),
        ("4x4x4 blindfolded", "444bf"),
        ("5x5x5 blindfolded", "555bf"),
        ("3x3x3 fewest moves", "333fm"),
        ("3x3x3 one handed", "333oh"),
        ("3x3x3 with feet", "333ft"),
        ("3x3x3 multi blind", "333mbf"),
        ("master magic", "mmagic"),
        ("award ceremony", "ceremony"),
        ("opening ceremony", "intro"),
        ("opening intro", "intro"),
        ("3x3x3 relay", "333relay"),
        ("3x3 relay", "333relay"),
        ("redi cube", "redi"),
        ("kilominx cube", "kilominx"),
        ("kilominx", "kilominx"),
        ("mirror blocks", "mirror"),
        ("mirror cube", "mirror"),
        ("ivy cube", "ivy"),
        ("face turning octahedron", "fto"),
        ("fto", "fto"),
        ("rubiks magic", "magic"),
        ("magic", "magic"),
        ("speed stacks", "stack"),
        ("registration", "registration"),
        ("lunch break", "lunch"),
        ("lunch", "lunch"),
        ("break", "break"),
        ("awards", "ceremony"),
        ("lucky event", "lucky"),
        ("funny event", "funny")
    ]

    static var isAvailable: Bool {
        UIFont(name: fontName, size: 12) != nil
    }

    static func glyph(for eventID: String, title: String? = nil) -> String? {
        let rawID = eventID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let glyph = glyphs[rawID] {
            return glyph
        }

        let activityEventID = rawID.components(separatedBy: "-r").first ?? rawID
        if let glyph = glyphs[activityEventID] {
            return glyph
        }

        for candidate in [eventID, title].compactMap({ $0 }) {
            let normalized = normalizedLookupKey(candidate)
            guard !normalized.isEmpty else { continue }

            if let alias = aliases.first(where: {
                normalized == $0.name || normalized.hasPrefix($0.name + " ")
            }), let glyph = glyphs[alias.eventID] {
                return glyph
            }
        }

        return nil
    }

    static func glyphMetrics(
        for glyph: String,
        fontName: String = CompetitionEventIconFont.fontName,
        pointSize: CGFloat
    ) -> GlyphMetrics? {
        guard let character = glyph.utf16.first else { return nil }
        let font = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        var source = character
        var renderedGlyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &source, &renderedGlyph, 1) else {
            return nil
        }

        var glyphCopy = renderedGlyph
        let bounds = CTFontGetBoundingRectsForGlyphs(font, .default, &glyphCopy, nil, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyphCopy, &advance, 1)
        return GlyphMetrics(bounds: bounds, advance: advance.width)
    }

    /// System menus do not preserve arbitrary custom-font `Text` labels. Render
    /// the canonical glyph to a template image before UIKit builds the menu.
    static func templateImage(
        for eventID: String,
        title: String? = nil,
        pointSize: CGFloat = 15
    ) -> UIImage? {
        guard ensureRegistered(),
              let glyph = glyph(for: eventID, title: title),
              let font = UIFont(name: fontName, size: pointSize) else { return nil }

        let attributedGlyph = NSAttributedString(
            string: glyph,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white
            ]
        )
        let inkBounds = attributedGlyph.boundingRect(
            with: CGSize(width: 128, height: 128),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        guard inkBounds.width > 0, inkBounds.height > 0 else { return nil }

        let inset: CGFloat = 1
        let size = CGSize(
            width: ceil(inkBounds.width + inset * 2),
            height: ceil(inkBounds.height + inset * 2)
        )
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            attributedGlyph.draw(
                at: CGPoint(
                    x: inset - inkBounds.minX,
                    y: inset - inkBounds.minY
                )
            )
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "×", with: "x")
            .lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    @discardableResult
    static func ensureRegistered() -> Bool {
        if isAvailable { return true }
        guard let fontURL = bundleFontURL() else { return false }

        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
        if didRegister { return true }

        if let error {
            let nsError = error.takeRetainedValue() as Error as NSError
            if nsError.domain == kCTFontManagerErrorDomain as String,
               nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
                return true
            }
        }

        return isAvailable
    }

    private static func bundleFontURL() -> URL? {
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf") {
            return url
        }
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf", subdirectory: "CompetitionIcons") {
            return url
        }
        if let url = Bundle.main.url(forResource: "event-icon", withExtension: "ttf", subdirectory: "Resources/CompetitionIcons") {
            return url
        }
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        for case let url as URL in enumerator where url.lastPathComponent == "event-icon.ttf" {
            return url
        }
        return nil
    }
}
