import Foundation

enum TNoodlePuzzleRegistry: Int, CaseIterable {
    // TNoodleLibNative's C entrypoint appears to follow Main.puzzles[] ordering,
    // which matches upstream PuzzleRegistry with FOUR_FAST omitted.
    case two = 0
    case three = 1
    case four = 2
    case five = 3
    case six = 4
    case seven = 5
    case threeNI = 6
    case fourNI = 7
    case fiveNI = 8
    case threeFM = 9
    case pyra = 10
    case sq1 = 11
    case mega = 12
    case clock = 13
    case skewb = 14
}

enum TNoodleScrambler {
    private static var discoveredIndices: [TNoodlePuzzleRegistry: Int] = [:]
    private static var lastDiagnostics: [TNoodlePuzzleRegistry: String] = [:]

    static func scramble(for registry: TNoodlePuzzleRegistry) -> String? {
        guard let validator = validator(for: registry) else {
            return TNoodleNativeBridge.scramble(forEventIndex: registry.rawValue)
        }

        return discoveredScramble(for: registry, validator: validator)
    }

    static func diagnostic(for registry: TNoodlePuzzleRegistry) -> String? {
        lastDiagnostics[registry]
    }

    private static func discoveredScramble(
        for registry: TNoodlePuzzleRegistry,
        validator: (String) -> Bool
    ) -> String? {
        if let error = TNoodleNativeBridge.initializationErrorDescription(), !error.isEmpty {
            lastDiagnostics[registry] = "\(registry.debugName) debug: init error: \(error)"
            return nil
        }

        if let discoveredIndex = discoveredIndices[registry],
           let scramble = TNoodleNativeBridge.scramble(forEventIndex: discoveredIndex),
           validator(scramble) {
            lastDiagnostics[registry] = "\(registry.debugName) debug: using cached index \(discoveredIndex)"
            return scramble
        }

        let validIndices = Array(0..<TNoodlePuzzleRegistry.allCases.count)
        let preferredIndices = registry.preferredProbeIndices.filter { validIndices.contains($0) }
        let candidateIndices = preferredIndices + validIndices.filter { !preferredIndices.contains($0) }
        var diagnostics: [String] = []
        for index in candidateIndices {
            guard let scramble = TNoodleNativeBridge.scramble(forEventIndex: index) else {
                if diagnostics.count < 8 {
                    diagnostics.append("\(index)=nil")
                }
                continue
            }

            let trimmed = scramble.trimmingCharacters(in: .whitespacesAndNewlines)
            if !validator(scramble) {
                if diagnostics.count < 8 {
                    diagnostics.append("\(index)=\(trimmed.prefix(24))")
                }
                continue
            }
            discoveredIndices[registry] = index
            lastDiagnostics[registry] = "\(registry.debugName) debug: matched index \(index)"
            return scramble
        }

        lastDiagnostics[registry] = diagnostics.isEmpty
            ? "\(registry.debugName) debug: no candidates returned a scramble"
            : "\(registry.debugName) debug: " + diagnostics.joined(separator: " | ")
        return nil
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
        default:
            return nil
        }
    }

    nonisolated private static func normalizedTokens(_ scramble: String) -> [String] {
        scramble
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
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

private extension TNoodlePuzzleRegistry {
    var debugName: String {
        switch self {
        case .pyra: return "Pyraminx"
        case .sq1: return "Sq1"
        case .mega: return "Megaminx"
        case .clock: return "Clock"
        case .skewb: return "Skewb"
        default: return "TNoodle"
        }
    }

    var preferredProbeIndices: [Int] {
        switch self {
        case .sq1:
            return [rawValue, 12]
        case .mega:
            return [rawValue, 13]
        case .clock:
            return [rawValue, 14]
        case .skewb:
            return [rawValue]
        default:
            return [rawValue]
        }
    }
}
