import Foundation

/// A consumed entry is never returned to the reserve; no cached scramble replay.
nonisolated struct ScrambleReserve: Equatable, Sendable {
    let capacity: Int
    private(set) var entries: [String] = []

    var needsRefill: Bool { entries.count < capacity }

    mutating func append(_ scramble: String) {
        guard needsRefill, !scramble.isEmpty else { return }
        entries.append(scramble)
    }

    mutating func take() -> String? {
        entries.isEmpty ? nil : entries.removeFirst()
    }
}
