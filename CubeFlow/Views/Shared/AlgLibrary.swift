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
