import Foundation
import Combine

/// One verified competitor, not a round scan or a numerical PR calculation.
@MainActor final class CubingChinaPersonalRecords: ObservableObject {
    @Published private(set) var rows: [CubingChinaLiveResult] = []
    private(set) var wcaID: String?
    private var requestID = UUID()
    private var loadedIdentity: String?
    private var evidence: String?

    static func association(ownWCAID: String?, candidates: [CubingChinaLiveResult.Competitor]) -> CubingChinaLiveResult.Competitor? {
        guard let own = CompetitionPersonalIdentity.canonical(ownWCAID) else { return nil }
        let matches = candidates.filter { CompetitionPersonalIdentity.canonical($0.wcaId) == own }
        let ids = Set(matches.map(\.id)), numbers = Set(matches.compactMap(\.number))
        guard ids.count == 1, numbers.count == 1, let number = numbers.first, number > 0,
              let first = matches.first(where: { $0.number == number }),
              !candidates.contains(where: { ($0.id == first.id || $0.number == number)
                  && CompetitionPersonalIdentity.canonical($0.wcaId) != own }) else { return nil }
        return first
    }

    func load(ownWCAID: String?, candidates: [CubingChinaLiveResult.Competitor], rounds: [CubingChinaLiveRound],
              evidence: String, refreshIdentity: String = "", fetch: (Int) async -> [CubingChinaLiveResult]?) async {
        let own = CompetitionPersonalIdentity.canonical(ownWCAID)
        if wcaID != own {
            requestID = UUID(); loadedIdentity = nil; self.evidence = nil; wcaID = own
            if !rows.isEmpty { rows = [] }
        }
        guard let own, let person = Self.association(ownWCAID: own, candidates: candidates), let number = person.number else {
            requestID = UUID(); loadedIdentity = nil; self.evidence = nil
            if !rows.isEmpty { rows = [] }
            return
        }
        let identity = "\(own)|\(person.id.rawValue)|\(number)|\(evidence)|\(refreshIdentity)"
        guard loadedIdentity != identity else { return }
        let token = UUID(); requestID = token
        guard let values = await fetch(number), !Task.isCancelled, requestID == token, wcaID == own,
              values.count <= 500, Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ value in
                  value.userId == person.id && value.competitor?.id == person.id && value.competitor?.number == number
                      && CompetitionPersonalIdentity.canonical(value.competitor?.wcaId) == own
                      && rounds.contains(where: { value.belongs(to: $0) })
              }) else { return }
        // Replacements include authoritative empty lists and removed PR flags.
        if rows != values { rows = values }
        self.evidence = evidence; loadedIdentity = identity
    }

    func tag(for round: CubingChinaLiveRound, ownWCAID: String?, evidence: String) -> String? {
        guard CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: wcaID),
              self.evidence == evidence else { return nil }
        return CubingLiveRecordIndicators.selector(rows.filter { $0.belongs(to: round) }.map {
            (CubingLiveRecordIndicators.display(regional: nil, personal: $0.personalSingleRecord),
             CubingLiveRecordIndicators.display(regional: nil, personal: $0.personalAverageRecord), $0.competitor?.wcaId)
        }, ownWCAID: ownWCAID)
    }
}
