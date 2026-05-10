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
    let group: String?
    let subgroup: String
    let imageKey: String
    let recognition: String
    let notes: String
    let setup: String?
    let algorithms: [AlgFormula]
    let algorithmGroups: [AlgFormulaGroup]?

    var displayAlgorithmsCount: Int {
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
}

struct AlgFormula: Decodable, Identifiable, Hashable {
    let id: String
    let notation: String
    let isPrimary: Bool
    let source: String
    let tags: [String]
}

enum AlgLibrarySet: String {
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
    case sq1CO = "sq1co"
    case sq1EO = "sq1eo"
    case sq1CP = "sq1cp"
    case sq1Parity = "sq1parity"
    case sq1LinPLL = "sq1linpll"
    case sq1LinParityPLL = "sq1linparitypll"
    case sq1EP = "sq1ep"
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
        case "sq1co": self = .sq1CO
        case "sq1eo": self = .sq1EO
        case "sq1cp": self = .sq1CP
        case "sq1parity": self = .sq1Parity
        case "sq1linpll": self = .sq1LinPLL
        case "sq1linparitypll": self = .sq1LinParityPLL
        case "sq1ep": self = .sq1EP
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
    static func load(_ set: AlgLibrarySet) -> AlgSetPayload? {
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
            return try JSONDecoder().decode(AlgSetPayload.self, from: data)
        } catch {
            assertionFailure("Failed to load \(set.resourceName).json: \(error)")
            return nil
        }
    }
}
