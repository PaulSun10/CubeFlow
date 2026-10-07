import SwiftUI

enum AlgCaseOrdering {
    static func sorted(_ cases: [AlgCase], by raw: String) -> [AlgCase] {
        guard raw != "default" else { return cases }
        return cases.enumerated().sorted { lhs, rhs in
            let a: Double, b: Double
            switch raw {
            case "likely": a = -(lhs.element.probabilityExact?.value ?? lhs.element.probability ?? -.infinity); b = -(rhs.element.probabilityExact?.value ?? rhs.element.probability ?? -.infinity)
            case "unlikely": a = lhs.element.probabilityExact?.value ?? lhs.element.probability ?? .infinity; b = rhs.element.probabilityExact?.value ?? rhs.element.probability ?? .infinity
            case "slices": a = Double(lhs.element.sliceCount ?? Int.max); b = Double(rhs.element.sliceCount ?? Int.max)
            default: return lhs.offset < rhs.offset
            }
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}

struct AlgCaseOrderingControls: View {
    let cases: [AlgCase]
    let puzzle: String
    @Binding var selection: String

    var body: some View {
        if supportsProbability || supportsSlices {
            Picker("algs.sort", selection: $selection) {
                Text("algs.sort_default").tag("default")
                if supportsProbability {
                    Text("algs.sort_likely").tag("likely")
                    Text("algs.sort_unlikely").tag("unlikely")
                }
                if supportsSlices { Text("algs.sort_slices").tag("slices") }
            }
            if supportsProbability { Text("algs.probability_basis") }
        }
    }

    private var supportsProbability: Bool { !cases.isEmpty && cases.allSatisfy { $0.probability != nil } }
    private var supportsSlices: Bool { puzzle == "SQ1" && cases.contains { $0.sliceCount != nil } }
}
