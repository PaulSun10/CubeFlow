import Foundation

/// Standard signed 30-degree pairs and self-inverse slices; never cube-token inversion.
nonisolated enum SquareOneNotation {
    enum Step: Equatable { case turn(Int, Int), slice }

    static func steps(_ notation: String) -> [Step]? {
        var result: [Step] = []
        for (index, segment) in notation.components(separatedBy: "/").enumerated() {
            if index > 0 { result.append(.slice) }
            let text = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            let bare: String
            if text.hasPrefix("("), text.hasSuffix(")") { bare = String(text.dropFirst().dropLast()) }
            else { bare = text }
            let pair = bare.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let top = Int(pair[0]), let bottom = Int(pair[1]),
                  (-6...6).contains(top), (-6...6).contains(bottom) else { return nil }
            result.append(.turn(top, bottom))
        }
        return result
    }

    static func normalized(_ notation: String) -> String? { steps(notation).map(format) }
    static func inverse(_ notation: String) -> String? {
        steps(notation).map { steps in format(steps.reversed().map {
            switch $0 { case .slice: .slice; case .turn(let a, let b): .turn(-a, -b) }
        }) }
    }

    private static func format(_ steps: [Step]) -> String {
        steps.map { switch $0 { case .slice: "/"; case .turn(let a, let b): "(\(a),\(b))" } }.joined(separator: " ")
    }
}
