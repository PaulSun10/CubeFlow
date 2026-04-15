import Foundation

enum AppLayoutLanguageCategory {
    case compactLatin
    case widerCJK
}

nonisolated func currentAppLanguageCode() -> String {
    let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    return stored.isEmpty ? "en" : stored
}

nonisolated func appLocalizationCandidates(for languageCode: String) -> [String] {
    let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.replacingOccurrences(of: "_", with: "-")
    let baseLanguage = normalized.split(separator: "-").first.map(String.init) ?? normalized

    var candidates: [String] = []
    for candidate in [normalized, trimmed, baseLanguage, "en"] {
        guard !candidate.isEmpty, !candidates.contains(candidate) else { continue }
        candidates.append(candidate)
    }
    return candidates
}

nonisolated func appLocalizedBundle(for languageCode: String) -> Bundle? {
    for candidate in appLocalizationCandidates(for: languageCode) {
        if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
    }
    return nil
}

nonisolated func appLocalizedString(_ key: String, languageCode: String, defaultValue: String? = nil) -> String {
    let fallbackValue = defaultValue ?? key
    if let bundle = appLocalizedBundle(for: languageCode) {
        let localized = bundle.localizedString(forKey: key, value: fallbackValue, table: nil)
        if localized != key || fallbackValue == key {
            return localized
        }
    }

    return Bundle.main.localizedString(forKey: key, value: fallbackValue, table: nil)
}

nonisolated func currentAppLocalizedString(_ key: String, defaultValue: String? = nil) -> String {
    appLocalizedString(key, languageCode: currentAppLanguageCode(), defaultValue: defaultValue)
}

nonisolated func appLocale(for languageCode: String) -> Locale {
    for candidate in appLocalizationCandidates(for: languageCode) {
        let identifier = candidate.replacingOccurrences(of: "-", with: "_")
        return Locale(identifier: identifier)
    }
    return Locale(identifier: "en")
}

nonisolated func appAcceptLanguageHeader(for languageCode: String) -> String {
    let candidates = appLocalizationCandidates(for: languageCode)
    var components: [String] = []
    var weight = 1.0

    for candidate in candidates {
        if components.contains(where: { $0.hasPrefix(candidate) }) { continue }
        if weight == 1.0 {
            components.append(candidate)
        } else {
            components.append("\(candidate);q=\(String(format: "%.1f", weight))")
        }
        weight = max(weight - 0.1, 0.5)
    }

    if !components.contains(where: { $0.hasPrefix("en") }) {
        components.append("en;q=0.5")
    }

    return components.joined(separator: ", ")
}

nonisolated func cubingLanguageCode(for languageCode: String) -> String {
    let candidates = appLocalizationCandidates(for: languageCode).map { $0.lowercased() }
    if candidates.contains("zh-hans") || candidates.contains("zh") {
        return "zh_cn"
    }
    return "en"
}

nonisolated func appLayoutLanguageCategory(for languageCode: String) -> AppLayoutLanguageCategory {
    let candidates = Set(appLocalizationCandidates(for: languageCode).map { $0.lowercased() })
    let cjkLanguageCodes: Set<String> = ["zh", "zh-hans", "zh-hant", "ja", "ko"]
    return !cjkLanguageCodes.isDisjoint(with: candidates) ? .widerCJK : .compactLatin
}
