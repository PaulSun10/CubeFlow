import SwiftUI
import UIKit

#if os(iOS)
/// Current cubing.com navigation tokens (entry.6hxXwaux.css / Bzh0emeU.js, 2026-10-08).
/// Hex values are rounded, sRGB-clipped conversions of the site's OKLCH/OKLab tokens.
enum CubingChinaNavigationColors {
    enum Section: CaseIterable {
        case about, regulations, schedule, travel, competitors, register, results, live, spectatorTicket, scrambles

        var foreground: Color {
            switch self {
            case .about: return adaptive(0xC10007, 0xFF6467) // red-700
            case .regulations: return adaptive(0xF54900, 0xD42300) // orange-600
            case .schedule: return adaptive(0xD08700, 0xB16A00) // yellow-600
            case .travel: return adaptive(0x008236, 0x05DF72) // green-700
            case .competitors: return adaptive(0x1447E6, 0x51A2FF) // blue-700
            case .register: return adaptive(0x45556C, 0xABB9CB) // fg-muted
            case .results: return adaptive(0x8200DB, 0xC27AFF) // purple-700
            case .live: return adaptive(0xC6005C, 0xFB64B6) // pink-700
            case .spectatorTicket: return adaptive(0x00786F, 0x00D5BE) // current site's teal-700 (cyan family)
            case .scrambles: return adaptive(0x0069A8, 0x00BCFF) // CubeFlow: sky-700 / sky-400
            }
        }

        var selectedBackground: Color {
            switch self {
            case .about: return adaptive(0xC10007, 0xE7000B) // red-700 / dark red-600
            case .regulations: return adaptive(0xFF6900, 0xDE4400) // orange-500
            case .schedule: return adaptive(0xF0B100, 0xC98B00) // yellow-500
            case .travel: return adaptive(0x00A63E, 0x00A63E) // green-600
            case .competitors: return adaptive(0x155DFC, 0x155DFC) // blue-600
            case .register: return adaptive(0x62748E, 0x62748E) // slate-500
            case .results: return adaptive(0x9810FA, 0x9810FA) // purple-600
            case .live: return adaptive(0xE60076, 0xE60076) // pink-600
            case .spectatorTicket: return adaptive(0x009689, 0x009689) // teal-600
            case .scrambles: return adaptive(0x0069A8, 0x0077A8) // sky; dark fill deepened for white text contrast
            }
        }
    }

    static func section(for kind: CompetitionDetailTabKind, about: Bool = false) -> Section? {
        switch kind {
        case .info: return about ? .about : nil
        case .rules: return .regulations
        case .schedule: return .schedule
        case .travel: return .travel
        case .competitors: return .competitors
        case .register: return .register
        case .results: return .results
        case .live: return .live
        case .scrambles: return .scrambles
        case .custom("spectator-ticket"): return .spectatorTicket
        default: return nil
        }
    }

    static func accent(for kind: CompetitionDetailTabKind, about: Bool = false) -> Color {
        section(for: kind, about: about)?.foreground ?? .primary
    }

    static func primaryAccent(for kind: CompetitionDetailTabKind, cubingChina: Bool, selected: Bool = false) -> Color {
        guard cubingChina else { return .accentColor }
        guard let section = section(for: kind) else { return .primary }
        return selected ? section.selectedBackground : section.foreground
    }

    static func selectedForeground(for kind: CompetitionDetailTabKind) -> Color {
        guard section(for: kind) != nil else { return Color(uiColor: .systemBackground) }
        return .white
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
#endif
