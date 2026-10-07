import Foundation

struct AlgCaseMembership: Decodable, Hashable {
    let setID: String
    let caseID: String
    let evidence: String
}

struct AlgCanonicalGroup: Decodable {
    let id: String
    let members: [AlgCaseMembership]
}

enum AlgCanonicalCases {
    private struct Manifest: Decodable { let version: Int; let groups: [AlgCanonicalGroup] }
    static let groups: [AlgCanonicalGroup] = {
        guard let url = Bundle.main.url(forResource: "canonical_relationships", withExtension: "json", subdirectory: "Resources/Algs")
                ?? Bundle.main.url(forResource: "canonical_relationships", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.version == 1 else { return [] }
        return manifest.groups
    }()
    private static let index: [String: Int] = {
        var result: [String: Int] = [:]
        for (offset, group) in groups.enumerated() {
            for member in group.members { result[key(member.setID, member.caseID)] = offset }
        }
        return result
    }()

    static func key(_ setID: String, _ caseID: String) -> String { setID.lowercased() + ":" + caseID }

    static func identity(setID: String, caseID: String) -> String {
        group(setID: setID, caseID: caseID)?.id ?? key(setID, caseID)
    }

    static func group(setID: String, caseID: String) -> AlgCanonicalGroup? {
        index[key(setID, caseID)].map { groups[$0] }
    }

    static func memberships(setID: String, caseID: String) -> [AlgCaseMembership] {
        group(setID: setID, caseID: caseID)?.members
            ?? [.init(setID: setID.lowercased(), caseID: caseID, evidence: "Local case identity")]
    }

    static func learned(setID: String, caseID: String, map: [String: Set<String>]) -> Bool {
        if map["__canonical_v1__", default: []].contains(identity(setID: setID, caseID: caseID)) { return true }
        return memberships(setID: setID, caseID: caseID).contains { map[$0.setID, default: []].contains($0.caseID) }
    }

    static func setLearned(_ learned: Bool, setID: String, caseID: String, map: inout [String: Set<String>]) {
        let id = identity(setID: setID, caseID: caseID)
        if learned { map["__canonical_v1__", default: []].insert(id) }
        else { map["__canonical_v1__", default: []].remove(id) }
        // Read old keys lazily; also write them for downgrade compatibility. Preserve unknown data.
        for member in memberships(setID: setID, caseID: caseID) {
            if learned { map[member.setID, default: []].insert(member.caseID) }
            else { map[member.setID, default: []].remove(member.caseID) }
        }
    }

    static func merge(_ pools: [(context: String, algorithms: [AlgFormula])]) -> [AlgFormula] {
        var result: [AlgFormula] = []
        var indices: [String: Int] = [:]
        for pool in pools {
            for algorithm in pool.algorithms {
                // Only whitespace-identical notation is deduplicated. No guessed move equivalence.
                let notation = algorithm.notation.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                let tags = Set(algorithm.tags + ["context:" + pool.context])
                if let index = indices[notation] {
                    let previous = result[index]
                    let sources = Set(previous.source.components(separatedBy: "; ") + [algorithm.source]).sorted()
                    result[index] = AlgFormula(id: previous.id, notation: previous.notation,
                        isPrimary: previous.isPrimary || algorithm.isPrimary, source: sources.joined(separator: "; "),
                        tags: Set(previous.tags).union(tags).sorted())
                } else {
                    indices[notation] = result.count
                    result.append(AlgFormula(id: pool.context + ":" + algorithm.id, notation: algorithm.notation,
                        isPrimary: algorithm.isPrimary, source: algorithm.source, tags: tags.sorted()))
                }
            }
        }
        return result
    }

    static func normalize(_ payload: AlgSetPayload) -> AlgSetPayload {
        let cases = payload.cases.map { item -> AlgCase in
            let siblings = memberships(setID: payload.set, caseID: item.id).compactMap { member -> (String, AlgCase)? in
                guard let set = AlgLibrarySet(rawValue: member.setID),
                      let value = (rawCases(set)[member.caseID]
                        ?? (set == .sq1PBL || set == .sq1EP ? rawCases(set == .sq1PBL ? .sq1PBLParity : .sq1EPParity)[member.caseID] : nil)) else { return nil }
                return (member.setID, value)
            }
            // A sole empty-setup orientation group is the same base pool, not a new pose.
            // Keep genuine direction-specific groups intact; never detach their setup context.
            guard siblings.count > 1, siblings.allSatisfy({ sibling in
                guard let groups = sibling.1.algorithmGroups, !groups.isEmpty else { return true }
                return groups.count == 1 && (groups[0].setup ?? "").isEmpty
                    && groups[0].algorithms.map(\.notation) == sibling.1.algorithms.map(\.notation)
            }) else { return item }
            var result = item
            if siblings.allSatisfy({ $0.1.setup == item.setup }) {
                result.algorithms = merge(siblings.map { (context: $0.0, algorithms: $0.1.algorithms) })
                if let first = item.algorithmGroups?.first {
                    result.algorithmGroups = [AlgFormulaGroup(id: first.id, title: first.title,
                        setup: first.setup, algorithms: result.algorithms)]
                }
            } else {
                // AUF-equivalent references may use different starting alignments. Keep those setups attached.
                result.algorithmGroups = siblings.map { set, value in
                    AlgFormulaGroup(id: set + ":" + value.id, title: set.uppercased(), setup: value.setup,
                        algorithms: merge([(context: set, algorithms: value.algorithms)]))
                }
            }
            return result
        }
        return AlgSetPayload(puzzle: payload.puzzle, set: payload.set, version: payload.version, source: payload.source, cases: cases)
    }

    private static var rawIndex: [AlgLibrarySet: [String: AlgCase]] = [:]

    private static func rawCases(_ set: AlgLibrarySet) -> [String: AlgCase] {
        if let cached = rawIndex[set] { return cached }
        var index: [String: AlgCase] = [:]
        for item in AlgLibraryLoader.loadRaw(set)?.cases ?? [] { index[item.id] = item }
        rawIndex[set] = index
        return index
    }
}
