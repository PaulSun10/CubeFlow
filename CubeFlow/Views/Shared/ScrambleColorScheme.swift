#if os(iOS)
import SwiftUI
import UIKit

struct ScrambleColorConfiguration: Codable, Equatable {
    var cube: [String]
    var pyraminx: [String]
    var skewb: [String]
    var squareOne: [String]
    var megaminx: [String]
    var clock: [String]
    var fto: [String] = ["#ffffff", "#44ee00", "#aaaaaa", "#ff8000", "#f4f400", "#2266ff", "#ff0000", "#8800dd"]

    static let `default` = ScrambleColorConfiguration(
        cube: ["#ffffff", "#ff0000", "#00dd00", "#ffff00", "#ffaa00", "#0000ff"],
        pyraminx: ["#00ff00", "#ff0000", "#0000ff", "#ffff00"],
        skewb: ["#ffffff", "#0000ff", "#ff0000", "#ffff00", "#00ff00", "#ff8800"],
        squareOne: ["#ffff00", "#ff8800", "#00ff00", "#ffffff", "#ff0000", "#0000ff"],
        megaminx: ["#ffffff", "#dd0000", "#006600", "#8844ff", "#ffcc00", "#0000bb", "#ffffbb", "#88ddff", "#ff8833", "#77ee00", "#ff99ff", "#999999"],
        clock: ["#ffffff", "#000000", "#000000", "#ffffff", "#919191", "#4c4c4c"]
    )

    enum CodingKeys: String, CodingKey { case cube, pyraminx, skewb, squareOne, megaminx, clock, fto }

    init(cube: [String], pyraminx: [String], skewb: [String], squareOne: [String], megaminx: [String], clock: [String], fto: [String]? = nil) {
        self.cube = cube; self.pyraminx = pyraminx; self.skewb = skewb
        self.squareOne = squareOne; self.megaminx = megaminx; self.clock = clock
        if let fto { self.fto = fto }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cube = try values.decode([String].self, forKey: .cube)
        pyraminx = try values.decode([String].self, forKey: .pyraminx)
        skewb = try values.decode([String].self, forKey: .skewb)
        squareOne = try values.decode([String].self, forKey: .squareOne)
        megaminx = try values.decode([String].self, forKey: .megaminx)
        clock = try values.decode([String].self, forKey: .clock)
        if let colors = try values.decodeIfPresent([String].self, forKey: .fto) { fto = colors }
    }

    static func decode(from data: Data?) -> ScrambleColorConfiguration {
        guard let data,
              let decoded = try? JSONDecoder().decode(ScrambleColorConfiguration.self, from: data) else {
            return .default
        }
        return decoded.normalized()
    }

    func encodedData() -> Data? {
        try? JSONEncoder().encode(normalized())
    }

    func colors(for puzzle: ScrambleColorPuzzle) -> [String] {
        switch puzzle {
        case .cube: return cube
        case .pyraminx: return pyraminx
        case .skewb: return skewb
        case .squareOne: return squareOne
        case .megaminx: return megaminx
        case .clock: return clock
        case .fto: return fto
        }
    }

    mutating func setColors(_ colors: [String], for puzzle: ScrambleColorPuzzle) {
        switch puzzle {
        case .cube: cube = colors
        case .pyraminx: pyraminx = colors
        case .skewb: skewb = colors
        case .squareOne: squareOne = colors
        case .megaminx: megaminx = colors
        case .clock: clock = colors
        case .fto: fto = colors
        }
    }

    func schemeString(for puzzleKey: String) -> String {
        switch ScrambleColorPuzzle(puzzleKey: puzzleKey) {
        case .cube:
            // draw-scramble nnn order is D, L, B, U, R, F.
            return [cube[safe: 3], cube[safe: 4], cube[safe: 5], cube[safe: 0], cube[safe: 1], cube[safe: 2]]
                .compactMap { $0 }
                .joined()
        case .pyraminx:
            return pyraminx.joined()
        case .skewb:
            return skewb.joined()
        case .squareOne:
            return squareOne.joined()
        case .megaminx:
            return megaminx.joined()
        case .clock:
            return clock.joined()
        case .fto:
            return fto.joined()
        }
    }

    private func normalized() -> ScrambleColorConfiguration {
        let defaults = ScrambleColorConfiguration.default
        return ScrambleColorConfiguration(
            cube: Self.normalized(cube, fallback: defaults.cube),
            pyraminx: Self.normalized(pyraminx, fallback: defaults.pyraminx),
            skewb: Self.normalized(skewb, fallback: defaults.skewb),
            squareOne: Self.normalized(squareOne, fallback: defaults.squareOne),
            megaminx: Self.normalized(megaminx, fallback: defaults.megaminx),
            clock: Self.normalized(clock, fallback: defaults.clock),
            fto: Self.normalized(fto, fallback: defaults.fto)
        )
    }

    private static func normalized(_ colors: [String], fallback: [String]) -> [String] {
        fallback.indices.map { index in
            guard colors.indices.contains(index), let normalized = normalizedHex(colors[index]) else {
                return fallback[index]
            }
            return normalized
        }
    }

    private static func normalizedHex(_ value: String) -> String? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#\(hex)"
    }
}

enum ScrambleColorPuzzle: String, CaseIterable, Identifiable {
    case cube
    case pyraminx
    case skewb
    case squareOne
    case megaminx
    case clock
    case fto

    var id: String { rawValue }

    init(puzzleKey: String) {
        switch puzzleKey {
        case "pyraminx": self = .pyraminx
        case "skewb": self = .skewb
        case "squareone": self = .squareOne
        case "megaminx": self = .megaminx
        case "clk": self = .clock
        case "fto": self = .fto
        default: self = .cube
        }
    }

    var title: String {
        switch self {
        case .cube: return "Cube"
        case .pyraminx: return "Pyraminx"
        case .skewb: return "Skewb"
        case .squareOne: return "Square-1"
        case .megaminx: return "Megaminx"
        case .clock: return "Clock"
        case .fto: return "FTO"
        }
    }

    var faceLabels: [String] {
        switch self {
        case .cube, .squareOne:
            return ["U", "R", "F", "D", "L", "B"]
        case .pyraminx:
            return ["Top", "Right", "Left", "Bottom"]
        case .skewb:
            return ["White", "Blue", "Red", "Yellow", "Green", "Orange"]
        case .megaminx:
            return (1...12).map { "Face \($0)" }
        case .fto:
            return ["U", "F", "BR", "BL", "D", "B", "R", "L"]
        case .clock:
            return ["Front Dial", "Back Dial", "Front Hand", "Back Hand", "Button Up", "Button Down"]
        }
    }

    var helpText: String {
        switch self {
        case .cube:
            return "Used by 2x2 through 7x7, OH, FMC, and blindfolded cube diagrams."
        case .clock:
            return "Clock uses dial, hand, and button colors instead of sticker faces."
        default:
            return "Used by this puzzle's scramble diagram."
        }
    }
}

extension Color {
    init(scrambleHex hex: String) {
        self.init(uiColor: UIColor(scrambleHex: hex))
    }

    func scrambleHexString() -> String {
        UIColor(self).scrambleHexString()
    }
}

extension UIColor {
    convenience init(scrambleHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    func scrambleHexString() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02x%02x%02x",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
