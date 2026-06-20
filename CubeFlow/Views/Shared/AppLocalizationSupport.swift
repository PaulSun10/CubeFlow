import Foundation

enum AppLayoutLanguageCategory {
    case compactLatin
    case widerCJK
}

struct AppLanguageOption: Identifiable, Hashable {
    let id: String
    let displayNameKey: String
    let nativeName: String
}

nonisolated func appLanguageOptions() -> [AppLanguageOption] {
    [
        AppLanguageOption(id: "en", displayNameKey: "settings.language_en", nativeName: "English"),
        AppLanguageOption(id: "zh-Hans", displayNameKey: "settings.language_zh", nativeName: "简体中文"),
        AppLanguageOption(id: "zh-Hant", displayNameKey: "settings.language_zh_hant", nativeName: "繁體中文"),
        AppLanguageOption(id: "ja", displayNameKey: "settings.language_ja", nativeName: "日本語"),
        AppLanguageOption(id: "ko", displayNameKey: "settings.language_ko", nativeName: "한국어"),
        AppLanguageOption(id: "es", displayNameKey: "settings.language_es", nativeName: "Español"),
        AppLanguageOption(id: "pt-BR", displayNameKey: "settings.language_pt_br", nativeName: "Português (Brasil)"),
        AppLanguageOption(id: "fr", displayNameKey: "settings.language_fr", nativeName: "Français"),
        AppLanguageOption(id: "de", displayNameKey: "settings.language_de", nativeName: "Deutsch"),
        AppLanguageOption(id: "it", displayNameKey: "settings.language_it", nativeName: "Italiano"),
        AppLanguageOption(id: "pl", displayNameKey: "settings.language_pl", nativeName: "Polski"),
        AppLanguageOption(id: "pt-PT", displayNameKey: "settings.language_pt_pt", nativeName: "Português (Portugal)"),
        AppLanguageOption(id: "id", displayNameKey: "settings.language_id", nativeName: "Bahasa Indonesia"),
        AppLanguageOption(id: "tr", displayNameKey: "settings.language_tr", nativeName: "Türkçe"),
        AppLanguageOption(id: "vi", displayNameKey: "settings.language_vi", nativeName: "Tiếng Việt"),
        AppLanguageOption(id: "ru", displayNameKey: "settings.language_ru", nativeName: "Русский"),
        AppLanguageOption(id: "th", displayNameKey: "settings.language_th", nativeName: "ไทย"),
        AppLanguageOption(id: "hi", displayNameKey: "settings.language_hi", nativeName: "हिन्दी"),
        AppLanguageOption(id: "ar", displayNameKey: "settings.language_ar", nativeName: "العربية")
    ]
}

nonisolated func currentAppLanguageCode() -> String {
    let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    return stored.isEmpty ? "en" : stored
}

nonisolated func appLanguageDisplayKey(for languageCode: String) -> String {
    appLanguageOptions().first(where: { $0.id == languageCode })?.displayNameKey ?? "settings.language_unknown"
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
    let normalized = languageCode
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "-")
        .lowercased()
    if normalized == "zh-hans" || normalized == "zh-cn" {
        return "zh_cn"
    }
    if normalized == "zh-hant" || normalized == "zh-tw" || normalized == "zh-hk" {
        return "zh_tw"
    }
    return "en"
}

nonisolated func appLayoutLanguageCategory(for languageCode: String) -> AppLayoutLanguageCategory {
    let candidates = Set(appLocalizationCandidates(for: languageCode).map { $0.lowercased() })
    let cjkLanguageCodes: Set<String> = ["zh", "zh-hans", "zh-hant", "ja", "ko"]
    return !cjkLanguageCodes.isDisjoint(with: candidates) ? .widerCJK : .compactLatin
}

nonisolated func appUsesRightToLeftLayout(for languageCode: String) -> Bool {
    let candidates = Set(appLocalizationCandidates(for: languageCode).map { $0.lowercased() })
    let rightToLeftLanguageCodes: Set<String> = ["ar"]
    return !rightToLeftLanguageCodes.isDisjoint(with: candidates)
}
