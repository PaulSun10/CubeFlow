import Foundation

struct AlgSetPayload: Decodable {
    let puzzle: String
    let set: String
    let version: Int
    let source: String
    let cases: [AlgCase]
}

struct AlgCase: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let name: String
    var group: String?
    let subgroup: String
    let imageKey: String
    let recognition: String
    let notes: String
    let setup: String?
    var algorithms: [AlgFormula]
    var algorithmGroups: [AlgFormulaGroup]?

    var stickers: [String: String]? = nil
    var probability: Double? = nil
    var probabilityExact: AlgExactProbability? = nil
    var probabilityBasis: String? = nil
    var csp: SquareOneCSPCase? = nil

    var sliceCount: Int? {
        let counts = algorithms.compactMap { formula -> Int? in
            guard let steps = SquareOneNotation.steps(formula.notation) else { return nil }
            return steps.filter { $0 == .slice }.count
        }
        return counts.min() ?? (setup == "" ? 0 : nil)
    }

    var displayAlgorithmsCount: Int {
        if csp != nil, let algorithmGroups {
            return Set(algorithmGroups.flatMap { $0.algorithms.map(\.id) }).count
        }
        guard let algorithmGroups, !algorithmGroups.isEmpty else {
            return algorithms.count
        }

        return algorithmGroups.reduce(into: 0) { total, group in
            total += group.algorithms.count
        }
    }

    var hasAlgorithmGroups: Bool {
        guard let algorithmGroups else { return false }
        return !algorithmGroups.isEmpty
    }
}

struct AlgFormulaGroup: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let setup: String?
    let algorithms: [AlgFormula]
    var executionAlignment: String? = nil
}

struct AlgFormula: Decodable, Identifiable, Hashable {
    let id: String
    let notation: String
    let isPrimary: Bool
    let source: String
    let tags: [String]
}

enum AlgLibrarySet: String, CaseIterable {
    case pll
    case oll
    case f2l
    case advancedF2L = "advancedf2l"
    case coll
    case wv
    case sv
    case cls
    case sbls
    case cmll
    case fourA = "4a"
    case vls
    case ollcp
    case zbll
    case oneLLL = "1lll"
    case ortegaOLL = "ortegaoll"
    case ortegaPBL = "ortegapbl"
    case cll
    case eg1
    case eg2
    case ollParity = "ollparity"
    case pllParity = "pllparity"
    case l2e
    case l2c
    case lin
    case sq1CS = "sq1cs"
    case sq1CSP = "sq1csp"
    case sq1CO = "sq1co"
    case sq1EO = "sq1eo"
    case sq1CP = "sq1cp"
    case sq1Parity = "sq1parity"
    case sq1LinPLL = "sq1linpll"
    case sq1LinParityPLL = "sq1linparitypll"
    case sq1EP = "sq1ep"
    case sq1PBL = "sq1pbl"
    case sq1EPParity = "sq1epparity"
    case sq1PBLParity = "sq1pblparity"
    case sq1OBL = "sq1obl"
    case ftoEdges = "ftoedges"
    case sq1LinPLL1 = "sq1linpll1"
    case megaminxOLL = "megaminxoll"
    case megaminxPLL = "megaminxpll"
    case megaminxEO = "megaminxeo"
    case megaminxCO = "megaminxco"
    case megaminxEP = "megaminxep"
    case megaminxCP = "megaminxcp"
    case l3e
    case l4e
    case sarahsAdvanced = "sarahsadvanced"

    var resourceName: String { rawValue }

    init?(itemID: String) {
        switch itemID.lowercased() {
        case "pll": self = .pll
        case "oll": self = .oll
        case "f2l": self = .f2l
        case "advancedf2l": self = .advancedF2L
        case "coll": self = .coll
        case "wv": self = .wv
        case "sv": self = .sv
        case "cls": self = .cls
        case "sbls": self = .sbls
        case "cmll": self = .cmll
        case "4a": self = .fourA
        case "vls": self = .vls
        case "ollcp": self = .ollcp
        case "zbll": self = .zbll
        case "1lll": self = .oneLLL
        case "ortegaoll": self = .ortegaOLL
        case "ortegapbl": self = .ortegaPBL
        case "cll": self = .cll
        case "eg1": self = .eg1
        case "eg2": self = .eg2
        case "ollparity": self = .ollParity
        case "pllparity": self = .pllParity
        case "l2e": self = .l2e
        case "l2c": self = .l2c
        case "lin": self = .lin
        case "sq1cs": self = .sq1CS
        case "sq1csp": self = .sq1CSP
        case "sq1co": self = .sq1CO
        case "sq1eo": self = .sq1EO
        case "sq1cp": self = .sq1CP
        case "sq1parity": self = .sq1Parity
        case "sq1linpll": self = .sq1LinPLL
        case "sq1linparitypll": self = .sq1LinParityPLL
        case "sq1ep": self = .sq1EP
        case "sq1pbl": self = .sq1PBL
        case "sq1obl": self = .sq1OBL
        case "ftoedges": self = .ftoEdges
        case "sq1linpll1": self = .sq1LinPLL1
        case "megaminxoll": self = .megaminxOLL
        case "megaminxpll": self = .megaminxPLL
        case "megaminxeo": self = .megaminxEO
        case "megaminxco": self = .megaminxCO
        case "megaminxep": self = .megaminxEP
        case "megaminxcp": self = .megaminxCP
        case "l3e": self = .l3e
        case "l4e": self = .l4e
        case "sarahsadvanced": self = .sarahsAdvanced
        default: return nil
        }
    }
}

enum AlgLibraryLoader {
    private static var normalizedCache: [AlgLibrarySet: AlgSetPayload] = [:]

    static func load(_ set: AlgLibrarySet) -> AlgSetPayload? {
        if let cached = normalizedCache[set] { return cached }
        guard var raw = loadRaw(set) else { return nil }
        if set == .sq1PBL || set == .sq1EP {
            let nonParity = raw.cases.map { item -> AlgCase in var value = item; value.group = "Non-parity"; return value }
            raw = AlgSetPayload(puzzle: raw.puzzle, set: raw.set, version: raw.version, source: raw.source, cases: nonParity + (loadRaw(set == .sq1PBL ? .sq1PBLParity : .sq1EPParity)?.cases ?? []))
        }
        let normalized = AlgCanonicalCases.normalize(raw)
        normalizedCache[set] = normalized
        return normalized
    }

    private static var payloadCache: [AlgLibrarySet: AlgSetPayload] = [:]

    static func loadRaw(_ set: AlgLibrarySet) -> AlgSetPayload? {
        if let cached = payloadCache[set] {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: set.resourceName,
            withExtension: "json",
            subdirectory: "Resources/Algs"
        ) ?? Bundle.main.url(
            forResource: set.resourceName,
            withExtension: "json"
        ) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(AlgSetPayload.self, from: data)
            payloadCache[set] = payload
            return payload
        } catch {
            assertionFailure("Failed to load \(set.resourceName).json: \(error)")
            return nil
        }
    }
}
