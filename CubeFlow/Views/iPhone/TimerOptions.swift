import SwiftUI

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

enum TimerFontDesignOption: String, CaseIterable, Identifiable {
    case `default`
    case expanded
    case compressed
    case condensed
    case monospaced
    case rounded
    case serif

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .default:
            return "settings.font_design_default"
        case .expanded:
            return "settings.font_design_expanded"
        case .compressed:
            return "settings.font_design_compressed"
        case .condensed:
            return "settings.font_design_condensed"
        case .monospaced:
            return "settings.font_design_monospaced"
        case .rounded:
            return "settings.font_design_rounded"
        case .serif:
            return "settings.font_design_serif"
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
        }
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

enum PuzzleEvent: String, CaseIterable {
    case twoByTwo = "2x2"
    case threeByThree = "3x3"
    case fourByFour = "4x4"
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
        case .fourByFour, .fourByFourBLD:
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
