import SwiftUI

enum WCAResultEmphasis: String, Codable, Hashable, Sendable {
    case personalBest = "pb"
    case worldRecord = "wr"
    case continentalRecord = "cr"
    case nationalRecord = "nr"

    var color: Color {
        switch self {
        case .personalBest:
            return Self.adaptiveColor(light: 0xFC4A0A, dark: 0xFF9B73)
        case .worldRecord:
            return Self.adaptiveColor(light: 0x0366D6, dark: 0x77B7FF)
        case .continentalRecord:
            return Self.adaptiveColor(light: 0xD00404, dark: 0xFF8585)
        case .nationalRecord:
            return Self.adaptiveColor(light: 0x28A745, dark: 0x72D68A)
        }
    }

    var marker: String? {
        switch self {
        case .personalBest: return nil
        case .worldRecord: return "WR"
        case .continentalRecord: return "CR"
        case .nationalRecord: return "NR"
        }
    }

    nonisolated static func from(cssClass: String) -> WCAResultEmphasis? {
        let classes = Set(cssClass.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
        if classes.contains("wr") { return .worldRecord }
        if classes.contains("cr") { return .continentalRecord }
        if classes.contains("nr") { return .nationalRecord }
        if classes.contains("pb") { return .personalBest }
        return nil
    }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(from: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(from rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum WCAProfileHighlightColor {
    static var medalSelection: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.42, green: 0.38, blue: 0.05, alpha: 1)
            }
            return UIColor(red: 1, green: 1, blue: 0.58, alpha: 1)
        })
    }
}

enum WCAMedalType: String, Codable, CaseIterable, Hashable, Sendable {
    case gold
    case silver
    case bronze

    var semanticColor: Color {
        Color(uiColor: UIColor { traits in
            let rgb: UInt32
            switch (self, traits.userInterfaceStyle) {
            case (.gold, .dark): rgb = 0xF2C94C
            case (.gold, _): rgb = 0xA97800
            case (.silver, .dark): rgb = 0xC8CDD3
            case (.silver, _): rgb = 0x68717C
            case (.bronze, .dark): rgb = 0xD58A57
            case (.bronze, _): rgb = 0xA65324
            }

            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum WCARankScope: Sendable {
    case world
    case continent
    case national

    var opacity: Double {
        switch self {
        case .world: return 1
        case .continent: return 0.8
        case .national: return 0.6
        }
    }

    func color(for rank: String?) -> Color {
        numericRank(rank) == 1 ? .red : .primary.opacity(opacity)
    }

    func fontWeight(for rank: String?) -> Font.Weight {
        numericRank(rank) == 1 ? .semibold : .medium
    }

    private func numericRank(_ rank: String?) -> Int? {
        guard let rank else { return nil }
        return Int(rank.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
