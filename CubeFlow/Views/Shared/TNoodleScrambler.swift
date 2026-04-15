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
    private static var discoveredSquareOneIndex: Int?
    private static var lastSquareOneDiagnostic: String?

    static func scramble(for registry: TNoodlePuzzleRegistry) -> String? {
        if registry == .sq1 {
            return squareOneScramble()
        }
        return TNoodleNativeBridge.scramble(forEventIndex: registry.rawValue)
    }

    static func diagnostic(for registry: TNoodlePuzzleRegistry) -> String? {
        guard registry == .sq1 else { return nil }
        return lastSquareOneDiagnostic
    }

    private static func squareOneScramble() -> String? {
        if let error = TNoodleNativeBridge.initializationErrorDescription(), !error.isEmpty {
            lastSquareOneDiagnostic = "Sq1 debug: init error: \(error)"
            return nil
        }

        if let discoveredSquareOneIndex,
           let scramble = TNoodleNativeBridge.scramble(forEventIndex: discoveredSquareOneIndex),
           isLikelySquareOneScramble(scramble) {
            lastSquareOneDiagnostic = "Sq1 debug: using cached index \(discoveredSquareOneIndex)"
            return scramble
        }

        // Official TNoodle PuzzleRegistry puts SQ1 at 12. Keep the historical local
        // index next, then probe the rest as a fallback because the native wrapper's
        // Main.puzzles ordering may differ from upstream.
        let preferredIndices = [TNoodlePuzzleRegistry.sq1.rawValue, 12]
        let candidateIndices = preferredIndices + Array(0...80).filter { !preferredIndices.contains($0) }
        var diagnostics: [String] = []
        for index in candidateIndices {
            guard let scramble = TNoodleNativeBridge.scramble(forEventIndex: index) else {
                if diagnostics.count < 8 {
                    diagnostics.append("\(index)=nil")
                }
                continue
            }

            let trimmed = scramble.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isLikelySquareOneScramble(scramble) {
                if diagnostics.count < 8 {
                    diagnostics.append("\(index)=\(trimmed.prefix(24))")
                }
                continue
            }
            discoveredSquareOneIndex = index
            lastSquareOneDiagnostic = "Sq1 debug: matched index \(index)"
            return scramble
        }

        lastSquareOneDiagnostic = diagnostics.isEmpty
            ? "Sq1 debug: no candidates returned a scramble"
            : "Sq1 debug: " + diagnostics.joined(separator: " | ")
        return nil
    }

    private static func isLikelySquareOneScramble(_ scramble: String) -> Bool {
        let trimmed = scramble.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains("("), trimmed.contains(")"), trimmed.contains(","), trimmed.contains("/") else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "0123456789-(),/ ").union(.whitespacesAndNewlines)
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
