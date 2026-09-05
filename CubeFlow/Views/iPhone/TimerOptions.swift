import SwiftUI
#if canImport(UIKit)
import Combine
import CoreText
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if os(iOS)
enum DrawScramblePlacement: String, CaseIterable, Identifiable {
    case inline
    case bottomLeft
    case bottomRight
    case bottomCenter
    case off

    var id: String { rawValue }

    var isFloating: Bool {
        switch self {
        case .bottomLeft, .bottomRight, .bottomCenter:
            return true
        case .inline, .off:
            return false
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .inline:
            return "settings.draw_scramble_position_inline"
        case .bottomLeft:
            return "settings.draw_scramble_position_bottom_left"
        case .bottomRight:
            return "settings.draw_scramble_position_bottom_right"
        case .bottomCenter:
            return "settings.draw_scramble_position_bottom_center"
        case .off:
            return "settings.draw_scramble_position_off"
        }
    }
}

enum ScrambleDisplayMode: String, CaseIterable, Identifiable {
    case shrinkFont
    case scroll

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .shrinkFont:
            return "settings.scramble_display_mode_shrink"
        case .scroll:
            return "settings.scramble_display_mode_scroll"
        }
    }
}

enum TimerFontDesignOption: String, CaseIterable, Identifiable {
    case `default`
    case rounded
    case expanded
    case condensed
    case compressed
    case serif
    case monospaced
    case academyEngraved
    case georgia
    case futura
    case skia
    case menlo
    case courierNew
    case americanTypewriter
    case copperplate
    case herculanum
    case chakraPetch
    case impact
    case dbLCDTempBlack
    case chalkboardSE
    case chalkduster
    case noteworthy
    case snellRoundhand
    case comicSansMS
    case papyrus

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .default:
            return "settings.font_design_default"
        case .rounded:
            return "settings.font_design_rounded"
        case .expanded:
            return "settings.font_design_expanded"
        case .condensed:
            return "settings.font_design_condensed"
        case .compressed:
            return "settings.font_design_compressed"
        case .serif:
            return "settings.font_design_serif"
        case .monospaced:
            return "settings.font_design_monospaced"
        case .academyEngraved:
            return "Academy Engraved LET"
        case .georgia:
            return "Georgia"
        case .futura:
            return "Futura"
        case .skia:
            return "Skia"
        case .menlo:
            return "Menlo"
        case .courierNew:
            return "Courier New"
        case .americanTypewriter:
            return "American Typewriter"
        case .copperplate:
            return "Copperplate"
        case .herculanum:
            return "Herculanum"
        case .chakraPetch:
            return "Chakra Petch"
        case .impact:
            return "Impact"
        case .dbLCDTempBlack:
            return "DB LCD Temp Black"
        case .chalkboardSE:
            return "Chalkboard SE"
        case .chalkduster:
            return "Chalkduster"
        case .noteworthy:
            return "Noteworthy"
        case .snellRoundhand:
            return "Snell Roundhand"
        case .comicSansMS:
            return "Comic Sans MS"
        case .papyrus:
            return "Papyrus"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .default, .expanded, .compressed, .condensed:
            return .default
        case .monospaced:
            return .monospaced
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .academyEngraved, .georgia, .futura, .skia, .menlo, .courierNew,
             .americanTypewriter, .copperplate, .herculanum, .chakraPetch,
             .impact, .dbLCDTempBlack, .chalkboardSE, .chalkduster, .noteworthy,
             .snellRoundhand, .comicSansMS, .papyrus:
            return .default
        }
    }

    var isFontWidthVariant: Bool {
        switch self {
        case .expanded, .condensed, .compressed:
            return true
        default:
            return false
        }
    }

    var resolvedCustomFontName: String? {
        guard let aliases = customFontAliases else { return nil }
        return Self.runtimeFontName(for: self) ?? aliases.first(where: {
            Self.platformHasFont(named: $0)
        })
    }

    var isAvailable: Bool {
        if isFontWidthVariant {
#if os(iOS)
            if #unavailable(iOS 16.0) { return false }
#elseif os(macOS)
            if #unavailable(macOS 13.0) { return false }
#endif
        }
        guard customFontAliases != nil else { return true }
        return resolvedCustomFontName != nil
    }

    var isSystemDownloadable: Bool {
#if canImport(UIKit)
        !isAvailable && downloadablePostScriptNames != nil
#else
        false
#endif
    }

    func font(size: Double, style: TimerFontStyleOption) -> Font {
        switch style.source {
        case .custom(let postScriptName):
            return .custom(postScriptName, size: size)
        case .system(let weight, let isItalic):
            let font = Font.system(size: size, weight: weight.fontWeight, design: fontDesign)
            return isItalic ? font.italic() : font
        }
    }

#if canImport(UIKit)
    func uiFont(size: CGFloat, style: TimerFontStyleOption) -> UIFont {
        switch style.source {
        case .custom(let postScriptName):
            return UIFont(name: postScriptName, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: .regular)
        case .system(let weight, let isItalic):
            let base = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
            let design: UIFontDescriptor.SystemDesign
            switch self {
            case .rounded: design = .rounded
            case .serif: design = .serif
            case .monospaced: design = .monospaced
            default: design = .default
            }
            var descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
            if isItalic, let italic = descriptor.withSymbolicTraits(.traitItalic) {
                descriptor = italic
            }
            if isFontWidthVariant {
                let width: CGFloat
                switch self {
                case .expanded: width = 0.22
                case .condensed: width = -0.22
                case .compressed: width = -0.42
                default: width = 0
                }
                var traits = descriptor.object(forKey: .traits)
                    as? [UIFontDescriptor.TraitKey: Any] ?? [:]
                traits[.width] = width
                descriptor = descriptor.addingAttributes([.traits: traits])
            }
            return UIFont(descriptor: descriptor, size: size)
        }
    }
#endif

    func availableStyles(preferredLegacyWeight: TimerFontWeightOption) -> [TimerFontStyleOption] {
        let styles = resolvedCustomFontName == nil
            ? systemFontStyles
            : customFontStyles
        guard !styles.isEmpty else {
            return [TimerFontStyleOption.system(weight: preferredLegacyWeight, isItalic: false)]
        }
        return styles
    }

    func resolvedStyle(
        rawValue: String,
        preferredLegacyWeight: TimerFontWeightOption
    ) -> TimerFontStyleOption {
        let styles = availableStyles(preferredLegacyWeight: preferredLegacyWeight)
        if let exact = styles.first(where: { $0.id == rawValue }) {
            return exact
        }

        let requestedWeight = TimerFontWeightOption(rawValue: rawValue) ?? preferredLegacyWeight
        return styles.min { lhs, rhs in
            let lhsDistance = abs(lhs.weightValue - requestedWeight.numericWeight)
                + (lhs.isItalic ? 0.08 : 0)
            let rhsDistance = abs(rhs.weightValue - requestedWeight.numericWeight)
                + (rhs.isItalic ? 0.08 : 0)
            return lhsDistance < rhsDistance
        } ?? styles[0]
    }

    static var availableOptions: [TimerFontDesignOption] {
        allCases.filter { $0.isAvailable || $0.isSystemDownloadable }
    }

    static func resolvedAvailableOption(rawValue: String) -> TimerFontDesignOption {
        guard let option = TimerFontDesignOption(rawValue: rawValue), option.isAvailable else {
            return .default
        }
        return option
    }

    private var customFontAliases: [String]? {
        switch self {
        case .default, .rounded, .expanded, .condensed, .compressed, .serif, .monospaced:
            return nil
        case .academyEngraved:
            return ["AcademyEngravedLetPlain", "Academy Engraved LET"]
        case .georgia:
            return ["Georgia"]
        case .futura:
            return ["Futura-Medium", "Futura"]
        case .skia:
            return ["Skia", "Skia-Regular"]
        case .menlo:
            return ["Menlo-Regular", "Menlo"]
        case .courierNew:
            return ["CourierNewPSMT", "Courier New"]
        case .americanTypewriter:
            return ["AmericanTypewriter", "American Typewriter"]
        case .copperplate:
            return ["Copperplate"]
        case .herculanum:
            return ["Herculanum"]
        case .chakraPetch:
            return ["ChakraPetch-Regular", "Chakra Petch"]
        case .impact:
            return ["Impact"]
        case .dbLCDTempBlack:
            return ["DBLCDTempBlack", "DB LCD Temp Black"]
        case .chalkboardSE:
            return ["ChalkboardSE-Regular", "Chalkboard SE"]
        case .chalkduster:
            return ["Chalkduster"]
        case .noteworthy:
            return ["Noteworthy-Light", "Noteworthy"]
        case .snellRoundhand:
            return ["SnellRoundhand", "Snell Roundhand"]
        case .comicSansMS:
            return ["ComicSansMS", "Comic Sans MS"]
        case .papyrus:
            return ["Papyrus"]
        }
    }

#if canImport(UIKit)
    private var downloadablePostScriptNames: [String]? {
        switch self {
        case .herculanum:
            return ["Herculanum"]
        case .chakraPetch:
            return [
                "ChakraPetch-Light", "ChakraPetch-LightItalic",
                "ChakraPetch-Regular", "ChakraPetch-Italic",
                "ChakraPetch-Medium", "ChakraPetch-MediumItalic",
                "ChakraPetch-SemiBold", "ChakraPetch-SemiBoldItalic",
                "ChakraPetch-Bold", "ChakraPetch-BoldItalic"
            ]
        case .comicSansMS:
            return ["ComicSansMS", "ComicSansMS-Bold"]
        case .skia:
            return ["Skia-Regular"]
        default:
            return nil
        }
    }

    func downloadSystemFontIfNeeded(
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws {
        guard !isAvailable else { return }
        guard let names = downloadablePostScriptNames else {
            throw TimerFontDownloadError.unavailable
        }

        let descriptors = names.map { name in
            CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: name
            ] as CFDictionary)
        }
        try await TimerFontDownloadRequest.download(
            descriptors: descriptors,
            progress: progress
        )
        guard isAvailable else { throw TimerFontDownloadError.unavailable }
    }
#endif

    private static func runtimeFontName(for requestedOption: TimerFontDesignOption) -> String? {
        let families = platformFontFamilyNames.map { family in
            (
                name: family,
                normalizedName: normalizedFontLookupName(family),
                fonts: platformFontNames(forFamilyName: family)
            )
        }

        guard let aliases = requestedOption.customFontAliases else { return nil }

        if let exact = aliases.first(where: { platformHasFont(named: $0) }) {
            return exact
        }

        let normalizedAliases = aliases.map(normalizedFontLookupName)

        for family in families where normalizedAliases.contains(family.normalizedName) {
            if let firstFont = family.fonts.first(where: platformHasFont(named:)) {
                return firstFont
            }
        }

        for family in families {
            if let matchingFont = family.fonts.first(where: { fontName in
                let normalizedFontName = normalizedFontLookupName(fontName)
                return normalizedAliases.contains(normalizedFontName)
                    || normalizedAliases.contains(where: {
                        normalizedFontName.hasPrefix($0) || $0.hasPrefix(normalizedFontName)
                    })
            }), platformHasFont(named: matchingFont) {
                return matchingFont
            }
        }
        return nil
    }

    private static var platformFontFamilyNames: [String] {
#if canImport(UIKit)
        UIFont.familyNames
#elseif canImport(AppKit)
        NSFontManager.shared.availableFontFamilies
#else
        []
#endif
    }

    private static func platformFontNames(forFamilyName familyName: String) -> [String] {
#if canImport(UIKit)
        UIFont.fontNames(forFamilyName: familyName)
#elseif canImport(AppKit)
        NSFontManager.shared.availableMembers(ofFontFamily: familyName)?
            .compactMap { $0.first as? String } ?? []
#else
        []
#endif
    }

    nonisolated private static func platformHasFont(named name: String) -> Bool {
#if canImport(UIKit)
        UIFont(name: name, size: 16) != nil
#elseif canImport(AppKit)
        NSFont(name: name, size: 16) != nil
#else
        false
#endif
    }

    nonisolated private static func normalizedFontLookupName(_ name: String) -> String {
        name.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { Character(String($0).lowercased()) }
            .reduce(into: "") { $0.append($1) }
    }

    private var customFontStyles: [TimerFontStyleOption] {
#if canImport(UIKit)
        guard let resolvedCustomFontName,
              let resolvedFont = UIFont(name: resolvedCustomFontName, size: 16) else {
            return []
        }

        return UIFont.fontNames(forFamilyName: resolvedFont.familyName)
            .compactMap { postScriptName -> TimerFontStyleOption? in
                guard let font = UIFont(name: postScriptName, size: 16) else { return nil }
                let faceName = font.fontDescriptor.object(forKey: .face) as? String
                let traits = font.fontDescriptor.object(forKey: .traits)
                    as? [UIFontDescriptor.TraitKey: Any]
                let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
                return TimerFontStyleOption(
                    id: "custom:\(postScriptName)",
                    name: faceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? postScriptName,
                    source: .custom(postScriptName: postScriptName),
                    weightValue: weight,
                    isItalic: font.fontDescriptor.symbolicTraits.contains(.traitItalic),
                    resolvedFaceSignature: TimerFontStyleOption.resolvedFaceSignature(
                        postScriptName: font.fontName,
                        faceName: faceName,
                        symbolicTraits: font.fontDescriptor.symbolicTraits
                    )
                )
            }
            .uniqued(by: \TimerFontStyleOption.resolvedFaceSignature)
            .sorted(by: TimerFontStyleOption.sortsBefore)
#else
        return []
#endif
    }

    private var systemFontStyles: [TimerFontStyleOption] {
#if canImport(UIKit)
        struct ResolvedSystemStyle {
            let requestedWeight: TimerFontWeightOption
            let resolvedWeight: TimerFontWeightOption
            let faceName: String
            let signature: String
        }

        let candidates = TimerFontWeightOption.allCases.compactMap { weight -> ResolvedSystemStyle? in
            guard let font = resolvedSystemFont(weight: weight) else { return nil }
            let descriptor = font.fontDescriptor
            let faceName = (descriptor.object(forKey: .face) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let traits = descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
            let descriptorWeight = (traits?[.weight] as? NSNumber)?.doubleValue ?? weight.numericWeight
            let resolvedWeight = TimerFontWeightOption.inferred(
                fromFaceDescription: [font.fontName, faceName].compactMap { $0 }.joined(separator: " ")
            ) ?? TimerFontWeightOption.nearest(to: descriptorWeight)
            let signature = TimerFontStyleOption.resolvedFaceSignature(
                postScriptName: font.fontName,
                faceName: faceName,
                symbolicTraits: descriptor.symbolicTraits
            )
            return ResolvedSystemStyle(
                requestedWeight: weight,
                resolvedWeight: resolvedWeight,
                faceName: faceName ?? resolvedWeight.englishName,
                signature: signature
            )
        }

        return Dictionary(grouping: candidates, by: { $0.signature })
            .values
            .compactMap { group in
                group.min {
                    abs($0.requestedWeight.numericWeight - $0.resolvedWeight.numericWeight)
                        < abs($1.requestedWeight.numericWeight - $1.resolvedWeight.numericWeight)
                }
            }
            .map { candidate in
                TimerFontStyleOption.system(
                    weight: candidate.requestedWeight,
                    isItalic: false,
                    resolvedName: candidate.faceName,
                    resolvedFaceSignature: candidate.signature
                )
            }
            .sorted(by: TimerFontStyleOption.sortsBefore)
#else
        return TimerFontWeightOption.allCases.map {
            TimerFontStyleOption.system(weight: $0, isItalic: false)
        }
#endif
    }

#if canImport(UIKit)
    private func resolvedSystemFont(weight: TimerFontWeightOption) -> UIFont? {
        let baseFont = UIFont.systemFont(ofSize: 16, weight: weight.uiFontWeight)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .rounded:
            design = .rounded
        case .serif:
            design = .serif
        case .monospaced:
            design = .monospaced
        default:
            design = .default
        }
        guard let descriptor = baseFont.fontDescriptor.withDesign(design) else { return nil }
        return UIFont(descriptor: descriptor, size: 16)
    }
#endif
}

#if canImport(UIKit)
enum TimerFontDownloadError: LocalizedError {
    case unavailable
    case couldNotStart
    case failed(Error?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This system font is not available on this device."
        case .couldNotStart:
            return "The system could not start downloading this font."
        case .failed(let error):
            return error?.localizedDescription ?? "The system could not download this font."
        }
    }
}

private final class TimerFontDownloadRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var firstError: Error?
    private var isFinished = false
    private let progressHandler: @Sendable (Double?) -> Void

    static func download(
        descriptors: [CTFontDescriptor],
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let request = TimerFontDownloadRequest(
                continuation: continuation,
                progressHandler: progress
            )
            let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
                descriptors as CFArray,
                Set([kCTFontNameAttribute]) as CFSet
            ) { state, progress in
                request.handle(state: state, progress: progress as NSDictionary)
            }
            if !started {
                request.finish(.failure(TimerFontDownloadError.couldNotStart))
            }
        }
    }

    private init(
        continuation: CheckedContinuation<Void, Error>,
        progressHandler: @escaping @Sendable (Double?) -> Void
    ) {
        self.continuation = continuation
        self.progressHandler = progressHandler
    }

    private func handle(
        state: CTFontDescriptorMatchingState,
        progress: NSDictionary
    ) -> Bool {
        switch state {
        case .willBeginQuerying, .stalled, .willBeginDownloading:
            progressHandler(nil)
        case .downloading:
            if let percentage = progress[kCTFontDescriptorMatchingPercentage] as? NSNumber {
                progressHandler(min(max(percentage.doubleValue / 100, 0), 1))
            } else {
                progressHandler(nil)
            }
        case .didFinishDownloading:
            progressHandler(1)
        case .didFailWithError:
            if let error = progress[kCTFontDescriptorMatchingError] as? Error {
                lock.lock()
                if firstError == nil { firstError = error }
                lock.unlock()
            }
        case .didFinish:
            lock.lock()
            let error = firstError
            lock.unlock()
            finish(error.map { .failure(TimerFontDownloadError.failed($0)) } ?? .success(()))
        default:
            break
        }
        return true
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

@MainActor
final class TimerFontDownloadManager: ObservableObject {
    enum State: Equatable {
        case downloading(Double?)
        case downloaded
        case failed(String)
    }

    static let shared = TimerFontDownloadManager()

    @Published private(set) var states: [TimerFontDesignOption: State] = [:]
    private var tasks: [TimerFontDesignOption: Task<Void, Never>] = [:]

    private init() { }

    func state(for option: TimerFontDesignOption) -> State? {
        if option.isAvailable { return .downloaded }
        return states[option]
    }

    func start(_ option: TimerFontDesignOption) {
        guard option.isSystemDownloadable,
              tasks[option] == nil else { return }

        states[option] = .downloading(nil)
        tasks[option] = Task { [weak self] in
            guard let self else { return }
            do {
                try await option.downloadSystemFontIfNeeded { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self,
                              case .downloading = self.states[option] else { return }
                        self.states[option] = .downloading(progress)
                    }
                }
                states[option] = .downloaded
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                states[option] = .failed(
                    message.isEmpty ? "The system could not download this font." : message
                )
            }
            tasks[option] = nil
        }
    }
}
#endif

struct TimerFontStyleOption: Identifiable, Hashable {
    enum Source: Hashable {
        case system(weight: TimerFontWeightOption, isItalic: Bool)
        case custom(postScriptName: String)
    }

    let id: String
    let name: String
    let source: Source
    let weightValue: Double
    let isItalic: Bool
    let resolvedFaceSignature: String

    static func system(
        weight: TimerFontWeightOption,
        isItalic: Bool,
        resolvedName: String? = nil,
        resolvedFaceSignature: String? = nil
    ) -> TimerFontStyleOption {
        TimerFontStyleOption(
            id: "system:\(weight.rawValue):\(isItalic ? "italic" : "roman")",
            name: (resolvedName ?? weight.englishName) + (isItalic ? " Italic" : ""),
            source: .system(weight: weight, isItalic: isItalic),
            weightValue: weight.numericWeight,
            isItalic: isItalic,
            resolvedFaceSignature: resolvedFaceSignature
                ?? "system:\(weight.rawValue):\(isItalic ? "italic" : "roman")"
        )
    }

#if canImport(UIKit)
    fileprivate static func resolvedFaceSignature(
        postScriptName: String,
        faceName: String?,
        symbolicTraits: UIFontDescriptor.SymbolicTraits
    ) -> String {
        let normalizedPostScriptName = normalizeFaceComponent(postScriptName)
        let normalizedFaceName = normalizeFaceComponent(faceName ?? "")
        let styleTraits = symbolicTraits.intersection([.traitItalic, .traitCondensed, .traitExpanded])
        return "\(normalizedPostScriptName)|\(normalizedFaceName)|\(styleTraits.rawValue)"
    }

    private static func normalizeFaceComponent(_ value: String) -> String {
        value.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { Character(String($0).lowercased()) }
            .reduce(into: "") { $0.append($1) }
    }
#endif

    nonisolated fileprivate static func sortsBefore(
        _ lhs: TimerFontStyleOption,
        _ rhs: TimerFontStyleOption
    ) -> Bool {
        if lhs.weightValue != rhs.weightValue { return lhs.weightValue < rhs.weightValue }
        if lhs.isItalic != rhs.isItalic { return !lhs.isItalic }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

enum TimerFontWeightOption: String, CaseIterable, Identifiable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .ultraLight:
            return "settings.font_weight_ultralight"
        case .thin:
            return "settings.font_weight_thin"
        case .light:
            return "settings.font_weight_light"
        case .regular:
            return "settings.font_weight_regular"
        case .medium:
            return "settings.font_weight_medium"
        case .semibold:
            return "settings.font_weight_semibold"
        case .bold:
            return "settings.font_weight_bold"
        case .heavy:
            return "settings.font_weight_heavy"
        case .black:
            return "settings.font_weight_black"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .ultraLight:
            return .ultraLight
        case .thin:
            return .thin
        case .light:
            return .light
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        case .black:
            return .black
        }
    }

    var englishName: String {
        switch self {
        case .ultraLight: return "Ultra Light"
        case .thin: return "Thin"
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .black: return "Black"
        }
    }

    var numericWeight: Double {
        switch self {
        case .ultraLight: return -0.8
        case .thin: return -0.6
        case .light: return -0.4
        case .regular: return 0
        case .medium: return 0.23
        case .semibold: return 0.3
        case .bold: return 0.4
        case .heavy: return 0.56
        case .black: return 0.62
        }
    }

#if canImport(UIKit)
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
#endif

    static func nearest(to numericWeight: Double) -> TimerFontWeightOption {
        allCases.min {
            abs($0.numericWeight - numericWeight) < abs($1.numericWeight - numericWeight)
        } ?? .regular
    }

    static func inferred(fromFaceDescription description: String) -> TimerFontWeightOption? {
        let normalized = description
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        if normalized.contains("ultra light") || normalized.contains("ultralight") { return .ultraLight }
        if normalized.contains("semi bold") || normalized.contains("semibold")
            || normalized.contains("demi bold") || normalized.contains("demibold") { return .semibold }
        if normalized.contains("extra bold") || normalized.contains("extrabold")
            || normalized.contains("ultra bold") || normalized.contains("ultrabold") { return .heavy }
        if normalized.contains("black") { return .black }
        if normalized.contains("heavy") { return .heavy }
        if normalized.contains("bold") { return .bold }
        if normalized.contains("medium") { return .medium }
        if normalized.contains("thin") { return .thin }
        if normalized.contains("light") { return .light }
        if normalized.contains("regular") || normalized.contains("roman")
            || normalized.contains("book") { return .regular }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

enum AverageDisplayOption: String, CaseIterable, Identifiable {
    case none
    case ao5
    case ao12
    case ao5AndAo12

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .none:
            return "settings.average_display_none"
        case .ao5:
            return "settings.average_display_ao5"
        case .ao12:
            return "settings.average_display_ao12"
        case .ao5AndAo12:
            return "settings.average_display_ao5_ao12"
        }
    }
}

enum GANResultInputMode: String, CaseIterable, Identifiable {
    case manual
    case cycle

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .manual:
            return "settings.gan_result_mode_manual"
        case .cycle:
            return "settings.gan_result_mode_cycle"
        }
    }

    var helpLocalizedKey: LocalizedStringKey {
        switch self {
        case .manual:
            return "settings.gan_result_mode_manual_help"
        case .cycle:
            return "settings.gan_result_mode_cycle_help"
        }
    }
}

enum SmartCubeFixedView: String, CaseIterable, Identifiable {
    case uf
    case urf

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .uf: "settings.smart_cube.view_uf"
        case .urf: "settings.smart_cube.view_urf"
        }
    }

    var yaw: Float {
        switch self {
        case .uf: 0
        case .urf: -0.68
        }
    }
}

enum SmartCubeResetPolicy: String, CaseIterable, Identifiable {
    case always
    case prompt
    case never

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .always: "settings.smart_cube.reset_always"
        case .prompt: "settings.smart_cube.reset_prompt"
        case .never: "settings.smart_cube.reset_never"
        }
    }
}

enum PuzzleEvent: String, CaseIterable {
    case twoByTwo = "2x2"
    case threeByThree = "3x3"
    case fourByFour = "4x4"
    case fourByFourFast = "4x4 fast"
    case fiveByFive = "5x5"
    case sixBySix = "6x6"
    case sevenBySeven = "7x7"
    case megaminx = "Megaminx"
    case pyraminx = "pyraminx"
    case square1 = "square-1"
    case clock = "clock"
    case skewb = "skewb"
    case threeByThreeOH = "3x3 oh"
    case threeByThreeFM = "3x3 fm"
    case threeByThreeBLD = "3x3 bld"
    case fourByFourBLD = "4x4 bld"
    case fiveByFiveBLD = "5x5 bld"
    case threeByThreeMBLD = "3x3 mbld"

    var localizationKey: String {
        switch self {
        case .twoByTwo: return "event.2x2"
        case .threeByThree: return "event.3x3"
        case .fourByFour: return "event.4x4"
        case .fourByFourFast: return "event.4x4fast"
        case .fiveByFive: return "event.5x5"
        case .sixBySix: return "event.6x6"
        case .sevenBySeven: return "event.7x7"
        case .megaminx: return "event.megaminx"
        case .pyraminx: return "event.pyraminx"
        case .square1: return "event.square1"
        case .clock: return "event.clock"
        case .skewb: return "event.skewb"
        case .threeByThreeOH: return "event.3x3oh"
        case .threeByThreeFM: return "event.3x3fm"
        case .threeByThreeBLD: return "event.3x3bld"
        case .fourByFourBLD: return "event.4x4bld"
        case .fiveByFiveBLD: return "event.5x5bld"
        case .threeByThreeMBLD: return "event.3x3mbld"
        }
    }

    static var regularCases: [PuzzleEvent] {
        [
            .twoByTwo,
            .threeByThree,
            .fourByFour,
            .fourByFourFast,
            .fiveByFive,
            .sixBySix,
            .sevenBySeven,
            .megaminx,
            .pyraminx,
            .square1,
            .clock,
            .skewb,
            .threeByThreeOH,
            .threeByThreeFM
        ]
    }

    static var regularTopLevelCases: [PuzzleEvent] {
        regularCases.filter { $0 != .fourByFour && $0 != .fourByFourFast }
    }

    static var fourByFourCases: [PuzzleEvent] {
        [.fourByFour, .fourByFourFast]
    }

    static var blindfoldedCases: [PuzzleEvent] {
        [
            .threeByThreeBLD,
            .fourByFourBLD,
            .fiveByFiveBLD,
            .threeByThreeMBLD
        ]
    }

    var scrambleDiagramPuzzleKey: String? {
        switch self {
        case .twoByTwo:
            return "222"
        case .threeByThree, .threeByThreeOH, .threeByThreeFM, .threeByThreeBLD:
            return "333"
        case .fourByFour, .fourByFourFast, .fourByFourBLD:
            return "444"
        case .fiveByFive, .fiveByFiveBLD:
            return "555"
        case .sixBySix:
            return "666"
        case .sevenBySeven:
            return "777"
        case .megaminx:
            return "megaminx"
        case .pyraminx:
            return "pyraminx"
        case .square1:
            return "squareone"
        case .clock:
            return "clk"
        case .skewb:
            return "skewb"
        case .threeByThreeMBLD:
            return nil
        }
    }
}
#endif
