import Foundation

nonisolated enum NumeralScope: String, CaseIterable, Sendable {
    case app
    case timer
    case statistics
}

nonisolated enum NumeralSystem: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case westernArabic
    case easternArabic
    case bangla
    case burmese
    case devanagari
    case gujarati
    case gurmukhi
    case kannada
    case khmer
    case malayalam
    case meitei
    case odia
    case olChiki
    case telugu
    case urdu
    case simplifiedChinese
    case traditionalChinese

    var id: String { rawValue }

    var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }

    var localizationKey: String {
        "settings.numeral_system.\(rawValue)"
    }

    var defaultTitle: String {
        switch self {
        case .systemDefault: "System Default"
        case .westernArabic: "Western Arabic"
        case .easternArabic: "Eastern Arabic"
        case .bangla: "Bangla"
        case .burmese: "Burmese"
        case .devanagari: "Devanagari"
        case .gujarati: "Gujarati"
        case .gurmukhi: "Gurmukhi"
        case .kannada: "Kannada"
        case .khmer: "Khmer"
        case .malayalam: "Malayalam"
        case .meitei: "Meitei"
        case .odia: "Odia"
        case .olChiki: "Ol Chiki"
        case .telugu: "Telugu"
        case .urdu: "Urdu"
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        }
    }

    fileprivate var foundationNumberingSystem: String? {
        switch self {
        case .systemDefault, .simplifiedChinese, .traditionalChinese: nil
        case .westernArabic: "latn"
        case .easternArabic: "arab"
        case .bangla: "beng"
        case .burmese: "mymr"
        case .devanagari: "deva"
        case .gujarati: "gujr"
        case .gurmukhi: "guru"
        case .kannada: "knda"
        case .khmer: "khmr"
        case .malayalam: "mlym"
        case .meitei: "mtei"
        case .odia: "orya"
        case .olChiki: "olck"
        case .telugu: "telu"
        case .urdu: "arabext"
        }
    }
}

nonisolated enum ChineseNumeralNumberFormat: String, CaseIterable, Identifiable, Sendable {
    case digits
    case chineseNumerals

    var id: String { rawValue }
}

nonisolated enum ChineseNumeralDecimalStyle: String, CaseIterable, Identifiable, Sendable {
    case period
    case chineseDecimal

    var id: String { rawValue }
}

nonisolated struct ChineseNumeralOptions: Equatable, Sendable {
    var financial = false
    var numberFormat = ChineseNumeralNumberFormat.digits
    var decimalStyle = ChineseNumeralDecimalStyle.period
}

nonisolated struct NumeralScopePreference: Equatable, Sendable {
    var system: NumeralSystem
    var chineseOptions: ChineseNumeralOptions
}

nonisolated enum NumeralPreferenceKeys {
    static let inheritedRawValue = "appNumerals"
    static let appSystem = "appNumeralSystem"
    static let timerSystem = "timerNumeralSystem"
    static let statisticsSystem = "statisticsNumeralSystem"

    static func financial(for scope: NumeralScope) -> String {
        "\(scope.rawValue)NumeralChineseFinancial"
    }

    static func numberFormat(for scope: NumeralScope) -> String {
        "\(scope.rawValue)NumeralChineseNumberFormat"
    }

    static func decimalStyle(for scope: NumeralScope) -> String {
        "\(scope.rawValue)NumeralChineseDecimalStyle"
    }
}

nonisolated struct NumeralPreferencesSnapshot: Equatable, Sendable {
    let app: NumeralScopePreference
    let timerOverride: NumeralScopePreference?
    let statisticsOverride: NumeralScopePreference?

    static let defaults = NumeralPreferencesSnapshot(
        app: NumeralScopePreference(system: .systemDefault, chineseOptions: ChineseNumeralOptions()),
        timerOverride: nil,
        statisticsOverride: nil
    )

    func resolved(for scope: NumeralScope) -> NumeralScopePreference {
        switch scope {
        case .app: app
        case .timer: timerOverride ?? app
        case .statistics: statisticsOverride ?? app
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> NumeralPreferencesSnapshot {
        let app = preference(
            scope: .app,
            rawSystem: defaults.string(forKey: NumeralPreferenceKeys.appSystem)
                ?? NumeralSystem.systemDefault.rawValue,
            defaults: defaults
        ) ?? NumeralPreferencesSnapshot.defaults.app
        return NumeralPreferencesSnapshot(
            app: app,
            timerOverride: preference(
                scope: .timer,
                rawSystem: defaults.string(forKey: NumeralPreferenceKeys.timerSystem)
                    ?? NumeralPreferenceKeys.inheritedRawValue,
                defaults: defaults
            ),
            statisticsOverride: preference(
                scope: .statistics,
                rawSystem: defaults.string(forKey: NumeralPreferenceKeys.statisticsSystem)
                    ?? NumeralPreferenceKeys.inheritedRawValue,
                defaults: defaults
            )
        )
    }

    private static func preference(
        scope: NumeralScope,
        rawSystem: String,
        defaults: UserDefaults
    ) -> NumeralScopePreference? {
        guard rawSystem != NumeralPreferenceKeys.inheritedRawValue else { return nil }
        let system = NumeralSystem(rawValue: rawSystem) ?? .systemDefault
        return NumeralScopePreference(
            system: system,
            chineseOptions: ChineseNumeralOptions(
                financial: defaults.bool(forKey: NumeralPreferenceKeys.financial(for: scope)),
                numberFormat: ChineseNumeralNumberFormat(
                    rawValue: defaults.string(forKey: NumeralPreferenceKeys.numberFormat(for: scope)) ?? ""
                ) ?? .digits,
                decimalStyle: ChineseNumeralDecimalStyle(
                    rawValue: defaults.string(forKey: NumeralPreferenceKeys.decimalStyle(for: scope)) ?? ""
                ) ?? .period
            )
        )
    }
}

nonisolated enum NumeralPresentation {
    static func verbatimIdentifier(_ value: String) -> String {
        value
    }

    static func formatInteger(
        _ value: Int,
        scope: NumeralScope = .app,
        preferences: NumeralPreferencesSnapshot? = nil
    ) -> String {
        presentNumericText(
            String(value),
            scope: scope,
            preferences: preferences
        )
    }

    static func formatLocalizedInteger(
        _ value: Int,
        template: String,
        scope: NumeralScope = .app,
        preferences: NumeralPreferencesSnapshot? = nil
    ) -> String {
        let presented = formatInteger(value, scope: scope, preferences: preferences)
        return template.replacingOccurrences(of: "%d", with: presented)
    }

    static func presentNumericText(
        _ numericText: String,
        scope: NumeralScope,
        preferences: NumeralPreferencesSnapshot? = nil
    ) -> String {
        let preference = (preferences ?? .load()).resolved(for: scope)
        switch preference.system {
        case .systemDefault:
            return numericText
        case .simplifiedChinese, .traditionalChinese:
            return presentChineseNumericText(numericText, preference: preference)
        default:
            guard let symbols = nativeSymbols[preference.system] else { return numericText }
            return String(numericText.flatMap { character -> [Character] in
                if let digit = character.wholeNumberValue, symbols.digits.indices.contains(digit) {
                    return [symbols.digits[digit]]
                }
                if character == "." {
                    return Array(symbols.decimalSeparator)
                }
                return [character]
            })
        }
    }

    private struct NativeSymbols {
        let digits: [Character]
        let decimalSeparator: String
    }

    private static let nativeSymbols: [NumeralSystem: NativeSymbols] = {
        Dictionary(uniqueKeysWithValues: NumeralSystem.allCases.compactMap { system in
            guard let identifier = system.foundationNumberingSystem else { return nil }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US@numbers=\(identifier)")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
            let digits = (0...9).compactMap { value in
                formatter.string(from: NSNumber(value: value))?.first
            }
            guard digits.count == 10 else { return nil }
            return (system, NativeSymbols(
                digits: digits,
                decimalSeparator: formatter.decimalSeparator ?? "."
            ))
        })
    }()

    private static func presentChineseNumericText(
        _ text: String,
        preference: NumeralScopePreference
    ) -> String {
        let timeComponents = text.split(separator: ":", omittingEmptySubsequences: false)
        if timeComponents.count == 2 {
            return presentChineseNumericText(String(timeComponents[0]), preference: preference)
                + "分"
                + presentChineseNumericText(String(timeComponents[1]), preference: preference)
        }
        if timeComponents.count == 3 {
            let hourUnit = preference.system == .traditionalChinese ? "時" : "时"
            return presentChineseNumericText(String(timeComponents[0]), preference: preference)
                + hourUnit
                + presentChineseNumericText(String(timeComponents[1]), preference: preference)
                + "分"
                + presentChineseNumericText(String(timeComponents[2]), preference: preference)
        }

        let characters = Array(text)
        var result = ""
        var index = 0

        while index < characters.count {
            guard characters[index].isNumber, characters[index].isASCII else {
                result.append(characters[index])
                index += 1
                continue
            }

            let integerStart = index
            while index < characters.count, characters[index].isNumber, characters[index].isASCII {
                index += 1
            }
            let integerDigits = String(characters[integerStart..<index])
            result += chineseInteger(integerDigits, preference: preference)

            if index < characters.count,
               characters[index] == ".",
               index + 1 < characters.count,
               characters[index + 1].isNumber,
               characters[index + 1].isASCII {
                result += preference.chineseOptions.decimalStyle == .period
                    ? "."
                    : (preference.system == .traditionalChinese ? "點" : "点")
                index += 1
                while index < characters.count, characters[index].isNumber, characters[index].isASCII {
                    result += chineseDigit(characters[index], preference: preference)
                    index += 1
                }
            }
        }
        return result
    }

    private static func chineseInteger(
        _ digits: String,
        preference: NumeralScopePreference
    ) -> String {
        guard preference.chineseOptions.numberFormat == .chineseNumerals,
              !(digits.count > 1 && digits.first == "0") else {
            return digits.map { chineseDigit($0, preference: preference) }.joined()
        }

        let trimmed = digits.drop { $0 == "0" }
        guard !trimmed.isEmpty else { return chineseDigit("0", preference: preference) }
        let normalized = String(trimmed)
        guard normalized.count <= 16 else {
            return normalized.map { chineseDigit($0, preference: preference) }.joined()
        }

        var sections: [Int] = []
        var end = normalized.endIndex
        while end > normalized.startIndex {
            let start = normalized.index(end, offsetBy: -min(4, normalized.distance(from: normalized.startIndex, to: end)))
            sections.insert(Int(normalized[start..<end]) ?? 0, at: 0)
            end = start
        }

        let sectionUnits = preference.system == .traditionalChinese
            ? ["", "萬", "億", "兆"]
            : ["", "万", "亿", "兆"]
        var result = ""
        var needsZero = false
        for (index, section) in sections.enumerated() {
            guard section != 0 else {
                if !result.isEmpty { needsZero = true }
                continue
            }
            if !result.isEmpty, needsZero || section < 1000 {
                result += chineseDigit("0", preference: preference)
            }
            result += chineseSection(section, preference: preference)
            result += sectionUnits[sections.count - index - 1]
            needsZero = false
        }
        return result
    }

    private static func chineseSection(
        _ value: Int,
        preference: NumeralScopePreference
    ) -> String {
        let units = preference.chineseOptions.financial
            ? ["", "拾", "佰", "仟"]
            : ["", "十", "百", "千"]
        let divisors = [1000, 100, 10, 1]
        var remaining = value
        var result = ""
        var pendingZero = false

        for (position, divisor) in divisors.enumerated() {
            let digit = remaining / divisor
            remaining %= divisor
            guard digit != 0 else {
                if !result.isEmpty, remaining > 0 { pendingZero = true }
                continue
            }
            if pendingZero {
                result += chineseDigit("0", preference: preference)
                pendingZero = false
            }
            let unitIndex = 3 - position
            let omitsLeadingOne = !preference.chineseOptions.financial
                && result.isEmpty
                && digit == 1
                && unitIndex == 1
            if !omitsLeadingOne {
                result += chineseDigit(Character(String(digit)), preference: preference)
            }
            result += units[unitIndex]
        }
        return result
    }

    private static func chineseDigit(
        _ character: Character,
        preference: NumeralScopePreference
    ) -> String {
        guard let value = character.wholeNumberValue else { return String(character) }
        let digits: [String]
        if preference.chineseOptions.financial {
            digits = preference.system == .traditionalChinese
                ? ["零", "壹", "貳", "參", "肆", "伍", "陸", "柒", "捌", "玖"]
                : ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        } else {
            digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        }
        return digits[value]
    }
}
