import Foundation

nonisolated struct SquareOneCSPCase: Decodable, Hashable {
    let shapeID: String
    let traceParity: Int
    let swapCount: Int
    let countingTop: Int
    let countingBottom: Int
    let convention: String
    let referenceTop: [Int]
    let referenceBottom: [Int]
}

/// Exact piece-cycle counting against an explicit same-shape reference, not color recognition.
nonisolated enum SquareOneCSP {
    /// Recognition allows independent layer alignment, not top/bottom swapping or reflection.
    static func presentationID(state: SquareOneState) -> String {
        func layer(_ a: [Int]) -> String {
            guard a.count == 12 else { return "" }
            let ring = a.enumerated().map { i, v in v == a[(i + 11) % 12] ? "0" : "1" }
            return (0..<12).map { r in (Array(ring[r...]) + Array(ring[..<r])).joined() }.min() ?? ""
        }
        return layer(state.top) + "|" + layer(state.bottom)
    }

    static func presentationPattern(state: SquareOneState) -> String {
        func layer(_ a: [Int]) -> String {
            guard a.count == 12 else { return "" }
            return a.enumerated().compactMap { i, v in
                v == a[(i + 11) % 12] ? nil : (v % 2 == 1 ? "C" : "E")
            }.joined()
        }
        return layer(state.top) + " / " + layer(state.bottom)
    }

    static func swapCount(state: SquareOneState, reference: SquareOneState, topOffset: Int = 0, bottomOffset: Int = 0) -> Int? {
        guard [state.top, state.bottom, reference.top, reference.bottom].allSatisfy({ $0.count == 12 }) else { return nil }
        func rotated(_ a: [Int], _ offset: Int) -> [Int] {
            let k = (offset % 12 + 12) % 12
            return Array(a[k...]) + Array(a[..<k])
        }
        let layers = [rotated(state.top, topOffset), rotated(state.bottom, bottomOffset)]
        let targets = [reference.top, reference.bottom]
        func pieces(_ a: [Int]) -> [Int] { a.enumerated().compactMap { i, v in v != a[(i + 11) % 12] ? v : nil } }
        for (a, b) in zip(layers, targets) {
            for i in 0..<12 {
                let previous = (i + 11) % 12
                let continuedPiece = a[i] == a[previous]
                let continuedReferencePiece = b[i] == b[previous]
                if continuedPiece != continuedReferencePiece { return nil }
            }
        }
        let ids: [Int] = layers.flatMap { pieces($0) }
        let goal: [Int] = targets.flatMap { pieces($0) }
        guard ids.count == 16, goal.count == 16, Set(ids) == Set(0..<16), Set(goal) == Set(0..<16) else { return nil }
        let permutation = ids.compactMap { goal.firstIndex(of: $0) }
        for i in 0..<16 where ids[i] % 2 != goal[i] % 2 { return nil }
        var visited = Set<Int>(), swaps = 0
        for i in 0..<16 where !visited.contains(i) {
            var j = i, length = 0
            repeat { visited.insert(j); length += 1; j = permutation[j] } while !visited.contains(j)
            swaps += length - 1
        }
        return swaps
    }
}
