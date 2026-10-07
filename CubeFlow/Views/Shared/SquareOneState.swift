import Foundation

/// Twelve 30-degree sectors per layer; repeated IDs identify unsplittable corners.
nonisolated struct SquareOneState: Equatable {
    var top = [0, 1, 1, 2, 3, 3, 4, 5, 5, 6, 7, 7]
    var bottom = [9, 9, 8, 11, 11, 10, 13, 13, 12, 15, 15, 14]
    var middleFlipped = false

    /// Rigid inversion across the slice plane. Piece IDs remain attached to pieces.
    var invertedPresentation: SquareOneState {
        SquareOneState(top: Array(bottom.reversed()), bottom: Array(top.reversed()), middleFlipped: middleFlipped)
    }

    mutating func apply(_ notation: String) -> Bool {
        guard let steps = SquareOneNotation.steps(notation) else { return false }
        var next = self
        for step in steps {
            switch step {
            case .turn(let a, let b):
                next.top = Self.rotated(next.top, by: a)
                next.bottom = Self.rotated(next.bottom, by: b)
            case .slice:
                guard next.isSliceable else { return false }
                let half = Array(next.top[6..<12])
                next.top.replaceSubrange(6..<12, with: next.bottom[0..<6])
                next.bottom.replaceSubrange(0..<6, with: half)
                next.middleFlipped.toggle()
            }
        }
        self = next
        return true
    }

    var isSliceable: Bool {
        [top, bottom].allSatisfy { $0[11] != $0[0] && $0[5] != $0[6] }
    }

    private static func rotated(_ values: [Int], by amount: Int) -> [Int] {
        let offset = (amount % 12 + 12) % 12
        return Array(values[offset...]) + Array(values[..<offset])
    }
}
