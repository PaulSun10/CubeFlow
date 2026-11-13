import Foundation

nonisolated enum TNoodlePuzzleRegistry: Int, CaseIterable {
    // The C ABI indexes Main.puzzles[], NOT PuzzleRegistry enum ordinals.
    // Pinned native source: e50c528, scrambles/PuzzleRegistry.java, class Main.
    case two = 0, three = 1, four = 2, five = 3, six = 4, seven = 5
    case sq1 = 6, mega = 7, pyra = 8, clock = 9, skewb = 10
    case threeFM = 11, threeNI = 12, fourNI = 13, fiveNI = 14
}

nonisolated enum TNoodleScrambler {
    private static let stateLock = NSLock()
    private static var lastDiagnostics: [TNoodlePuzzleRegistry: String] = [:]

    static func scramble(for registry: TNoodlePuzzleRegistry) -> String? {
        stateLock.lock(); defer { stateLock.unlock() }
        let result = scramble(for: registry, using: { TNoodleNativeBridge.scramble(forEventIndex: $0) })
        lastDiagnostics[registry] = registry == .threeFM && result == nil
            ? "FMC generation unavailable: native state or verified presentation search failed." : nil
        return result
    }

    // Injectable boundary, with no global mock state and no index probing. Notation
    // validation can reject corruption but cannot identify one cube size as another.
    static func scramble(for registry: TNoodlePuzzleRegistry, using generate: (Int) -> String?) -> String? {
        // Slot 11 is not the dedicated FMC class. Reuse native 3x3's target
        // distribution, then preserve that exact target under FMC padding.
        if registry == .threeFM {
            guard let native = scramble(for: .three, using: generate) else { return nil }
            return Min2PhaseBridge.fmcScramble(from: native)
        }
        guard let result = generate(registry.rawValue),
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let validate = validator(for: registry), !validate(result) { return nil }
        return result
    }

    static func diagnostic(for registry: TNoodlePuzzleRegistry) -> String? {
        stateLock.lock(); defer { stateLock.unlock() }; return lastDiagnostics[registry]
    }

    private static func validator(for registry: TNoodlePuzzleRegistry) -> ((String) -> Bool)? {
        switch registry {
        case .pyra:
            return isLikelyPyraminxScramble
        case .sq1:
            return isLikelySquareOneScramble
        case .mega:
            return isLikelyMegaminxScramble
        case .clock:
            return isLikelyClockScramble
        case .skewb:
            return isLikelySkewbScramble
        case .two, .three, .four, .five, .six, .seven, .threeNI, .fourNI, .fiveNI:
            return { value in
                let tokens = value.split(whereSeparator: \.isWhitespace)
                return !tokens.isEmpty && tokens.allSatisfy {
                    $0.range(of: #"^(?:[234]?[URFDLB]w?|[xyz])(?:2|')?$"#, options: .regularExpression) != nil
                }
            }
        default:
            return nil
        }
    }

    nonisolated private static func normalizedTokens(_ scramble: String) -> [String] {
        scramble
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    nonisolated private static func isLikelySquareOneScramble(_ scramble: String) -> Bool {
        let trimmed = scramble.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains("("), trimmed.contains(")"), trimmed.contains(","), trimmed.contains("/") else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "0123456789-(),/ ").union(.whitespacesAndNewlines)
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    nonisolated private static func isLikelyMegaminxScramble(_ scramble: String) -> Bool {
        let tokens = normalizedTokens(scramble)
        let allowed = Set(["R++", "R--", "D++", "D--", "U", "U'"])
        return !tokens.isEmpty && tokens.allSatisfy { allowed.contains($0) }
    }

    nonisolated private static func isLikelyClockScramble(_ scramble: String) -> Bool {
        let tokens = normalizedTokens(scramble)
        guard tokens.contains(where: { $0.hasPrefix("UR") || $0.hasPrefix("DR") || $0.hasPrefix("DL") || $0.hasPrefix("UL") || $0.hasPrefix("ALL") }) else {
            return false
        }
        let joined = tokens.joined(separator: " ")
        return !joined.contains("Rw") && !joined.contains("Uw") && !joined.contains("Fw") && !joined.contains("Bw")
    }

    nonisolated private static func isLikelySkewbScramble(_ scramble: String) -> Bool {
        let tokens = normalizedTokens(scramble)
        let allowed = Set(["R", "R'", "U", "U'", "L", "L'", "B", "B'"])
        return !tokens.isEmpty && tokens.allSatisfy { allowed.contains($0) }
    }

    nonisolated private static func isLikelyPyraminxScramble(_ scramble: String) -> Bool {
        let tokens = normalizedTokens(scramble)
        let allowed = Set(["R", "R'", "L", "L'", "U", "U'", "B", "B'", "r", "r'", "l", "l'", "u", "u'", "b", "b'"])
        return !tokens.isEmpty && tokens.allSatisfy { allowed.contains($0) }
    }
}
