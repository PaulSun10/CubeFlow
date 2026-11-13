import SwiftUI

enum AlgCaseOrdering {
    static func sorted(_ cases: [AlgCase], by raw: String) -> [AlgCase] {
        let key: (AlgCase) -> Double
        switch raw {
        case "likely": key = { -($0.probabilityExact?.value ?? $0.probability ?? -.infinity) }
        case "unlikely": key = { $0.probabilityExact?.value ?? $0.probability ?? .infinity }
        case "slices": key = { Double($0.sliceCount ?? Int.max) }
        default: return cases
        }
        // Slice count parses notation. Compute it once per case, not on each comparison.
        var order = cases.indices.map { (index: $0, key: key(cases[$0])) }
        order.sort { $0.key == $1.key ? $0.index < $1.index : $0.key < $1.key }
        return order.map { cases[$0.index] }
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
