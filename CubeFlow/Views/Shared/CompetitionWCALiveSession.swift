import Foundation
import Combine

/// A competition-detail lifetime. Only the active round owns a subscription;
/// retained snapshots are last-known presentation, never a fictional server revision.
@MainActor final class CompetitionWCALiveSession: ObservableObject {
    @Published private(set) var content: CompetitionWCALiveContent?
    @Published private(set) var personalResults: [CompetitionWCALiveCompetitorResult] = []
    @Published private(set) var homeVisit = 0
    private struct Entry {
        let round: CompetitionWCALiveRound
        let baseEpoch: Int
    }
    private var base: CompetitionWCALiveContent?
    private var competitionID: Int?
    private var language = "en"
    private var baseEpoch = 0
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var roundVersions: [String: Int] = [:]
    private var regionalEvidence = CompetitionWCALiveRecordLedger()
    private weak var active: CompetitionWCALiveRealtimeManager?
    private var ownWCAID: String?
    private var ownPersonID: String?
    private var personalEpoch: Int?
    private var personalRequest = UUID()
    private var personalLoadedKey: String?
    private var personalRoundOverrides: [String: [CompetitionWCALiveCompetitorResult]] = [:]
    private let personRequests = CompetitionRequestPool<CompetitionWCALiveCompetitorContent?>()
    private let roundLimit: Int
    private let rowLimit: Int
    private let personLoader: @Sendable (String, String) async -> CompetitionWCALiveCompetitorContent?

    init(roundLimit: Int = 12, rowLimit: Int = 20_000,
         personLoader: @escaping @Sendable (String, String) async -> CompetitionWCALiveCompetitorContent? = {
             await CompetitionService.fetchWCALiveCompetitorContent(personID: $0, languageCode: $1)
         }) {
        self.roundLimit = roundLimit; self.rowLimit = rowLimit; self.personLoader = personLoader
    }

    func configure(_ value: CompetitionWCALiveContent, language: String) {
        guard value.competitionID > 0, value.rounds.count <= 500,
              Set(value.rounds.map(\.id)).count == value.rounds.count,
              (value.competitors?.count ?? 0) <= 20_000 else { return }
        if competitionID != value.competitionID || self.language != language {
            active?.stop(); active = nil
            competitionID = value.competitionID; self.language = language
            entries = [:]; order = []; roundVersions = [:]; regionalEvidence = CompetitionWCALiveRecordLedger()
            base = nil
            clearPersonal()
        }
        guard base != value else { return }
        let keepsPersonalIdentity = base?.competitors == value.competitors
            && base?.rounds.map { "\($0.id)|\($0.eventID)|\($0.number ?? 0)" }.sorted()
                == value.rounds.map { "\($0.id)|\($0.eventID)|\($0.number ?? 0)" }.sorted()
        let hadPersonalEvidence = personalEpoch != nil
        base = value; baseEpoch += 1
        personalRequest = UUID(); personalLoadedKey = nil
        // Refreshing metadata does not itself retract known personal flags. Keep
        // them while the same verified person/round scope revalidates.
        personalEpoch = keepsPersonalIdentity && hadPersonalEvidence ? baseEpoch : nil
        personalRoundOverrides = [:]
        let valid = Set(value.rounds.map(\.id))
        entries = entries.filter { valid.contains($0.key) }; order.removeAll { !valid.contains($0) }
        roundVersions = roundVersions.filter { valid.contains($0.key) }
        regionalEvidence.retainRounds(valid)
        let metadataTime = value.clientRequestContext?.currentProcessTime ?? -.greatestFiniteMagnitude
        if let records = value.records {
            for round in value.rounds {
                regionalEvidence.full(records.filter { $0.roundID == round.id
                    && PublishedCompetitionResult.recordBadge($0.tag) != nil }, roundID: round.id, observedAt: metadataTime)
            }
        }
        for round in value.rounds where value.loadedRoundIDs?.contains(round.id) == true && entries[round.id] == nil {
            retain(round)
            regionalEvidence.full(Self.regionalRecords(round), roundID: round.id, observedAt: metadataTime)
        }
        publishContent()
        active?.refresh()
    }
    func beginHomeVisit() { homeVisit += 1 }

    func knownRound(_ metadata: CompetitionWCALiveRound, competitionID: Int, language: String) -> CompetitionWCALiveRound? {
        guard self.competitionID == competitionID, self.language == language,
              let value = entries[metadata.id]?.round, value.eventID == metadata.eventID,
              value.number == metadata.number else { return nil }
        return value
    }
    func activate(_ manager: CompetitionWCALiveRealtimeManager, competitionID: Int, language: String) {
        if self.competitionID != competitionID || self.language != language {
            active?.stop(); base = nil; content = nil; entries = [:]; order = []; roundVersions = [:]
            regionalEvidence = CompetitionWCALiveRecordLedger()
            self.competitionID = competitionID; self.language = language; baseEpoch += 1; clearPersonal()
        }
        if active !== manager { active?.stop(); active = manager }
        touch(manager.round.id)
        manager.start()
    }
    func deactivate(_ manager: CompetitionWCALiveRealtimeManager) {
        guard active === manager else { return }
        manager.stop(); active = nil
    }
    func accept(_ round: CompetitionWCALiveRound, competitionID: Int, language: String) {
        guard self.competitionID == competitionID, self.language == language,
              round.results.count <= rowLimit, Set(round.results.map(\.id)).count == round.results.count,
              base?.rounds.contains(where: { $0.id == round.id && $0.eventID == round.eventID && $0.number == round.number }) != false else { return }
        roundVersions[round.id, default: 0] += 1
        regionalEvidence.full(Self.regionalRecords(round), roundID: round.id, observedAt: ProcessInfo.processInfo.systemUptime)
        retain(round)
        if let ownPersonID, let ownWCAID {
            let mine = round.results.filter { $0.personID == ownPersonID
                && CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: $0.personWCAID) }
            personalRoundOverrides[round.id] = mine.map { Self.personalResult($0, round: round) }
            if personalEpoch == baseEpoch {
                let updated = personalResults.filter { $0.roundID != round.id } + (personalRoundOverrides[round.id] ?? [])
                if personalResults != updated { personalResults = updated }
            }
        }
        publishContent()
    }
    private func retain(_ round: CompetitionWCALiveRound) {
        guard round.results.count <= rowLimit else { return }
        entries[round.id] = Entry(round: round, baseEpoch: baseEpoch); touch(round.id)
        while order.count > roundLimit || entries.values.reduce(0, { $0 + $1.round.results.count }) > rowLimit {
            entries[order.removeFirst()] = nil
        }
    }
    private func touch(_ id: String) { order.removeAll { $0 == id }; if entries[id] != nil { order.append(id) } }
    private func publishContent() {
        guard let base else { return }
        let rounds = base.rounds.map { metadata in
            guard let cached = entries[metadata.id]?.round, cached.eventID == metadata.eventID else { return metadata }
            return Self.withResults(cached.results, metadata: metadata)
        }
        var records = regionalEvidence.records
        // Ordering is stable even when dictionary storage order changes.
        records.sort { $0.id < $1.id }
        let value = CompetitionWCALiveContent(competitionID: base.competitionID, competitionName: base.competitionName,
            eventIDs: base.eventIDs, rounds: rounds, venues: base.venues, records: records,
            competitors: base.competitors, loadedRoundIDs: base.loadedRoundIDs,
            clientRequestContext: base.clientRequestContext)
        if content != value { content = value }
    }

    func roundTag(_ roundID: String, ownWCAID: String?) -> String? {
        let records = content?.records?.filter { $0.roundID == roundID } ?? []
        if let regional = PublishedCompetitionResult.highestBadge(records.map(\.tag)) { return regional }
        guard CompetitionPersonalIdentity.matches(signedInWCAID: ownWCAID, competitorWCAID: self.ownWCAID),
              personalEpoch == baseEpoch else { return nil }
        return personalResults.contains { $0.roundID == roundID && [$0.singleRecordTag, $0.averageRecordTag].contains("PR") } ? "PR" : nil
    }
    func eventTag(_ eventID: String, ownWCAID: String?) -> String? {
        CubingLiveRecordIndicators.highestDisplay((content?.rounds.filter { $0.eventID == eventID } ?? [])
            .map { roundTag($0.id, ownWCAID: ownWCAID) })
    }
    var personalIdentity: String { "\(competitionID ?? 0)|\(baseEpoch)|\(homeVisit)" }
    func loadPersonalRecords(ownWCAID: String?) async {
        let own = CompetitionPersonalIdentity.canonical(ownWCAID)
        if self.ownWCAID != own { clearPersonal(); self.ownWCAID = own }
        guard let own, let base,
              let people = base.competitors else { return }
        let matches = people.filter { CompetitionPersonalIdentity.canonical($0.wcaID) == own }
        guard matches.count == 1, let person = matches.first, !person.id.isEmpty,
              people.filter({ $0.id == person.id }).count == 1 else { clearPersonal(); self.ownWCAID = own; return }
        let key = "\(personalIdentity)|\(own)|\(person.id)|\(language)"
        guard key != personalLoadedKey else { return }
        let request = UUID(); personalRequest = request
        let epoch = baseEpoch, versions = roundVersions, loader = personLoader, language = language
        let requestedAt = ProcessInfo.processInfo.systemUptime
        ownPersonID = person.id
        guard let value = try? await personRequests.value(key: key, loader: { await loader(person.id, language) }),
              !Task.isCancelled, personalRequest == request, baseEpoch == epoch, self.ownWCAID == own,
              value.id == person.id, CompetitionPersonalIdentity.canonical(value.wcaID) == own,
              value.results.count <= 500, Set(value.results.map(\.id)).count == value.results.count,
              value.results.allSatisfy({ result in base.rounds.contains {
                  $0.id == result.roundID && $0.eventID == result.eventID && $0.number == result.roundNumber
              } }) else { return }
        var rows = value.results
        for round in base.rounds where versions[round.id, default: 0] != roundVersions[round.id, default: 0] {
            rows.removeAll { $0.roundID == round.id }
            rows += personalRoundOverrides[round.id] ?? []
        }
        personalEpoch = epoch; personalLoadedKey = key
        if personalResults != rows { personalResults = rows }
        for round in base.rounds {
            let mine = rows.filter { $0.roundID == round.id }.map { row in
                CompetitionWCALiveResultPreview(id: row.id, ranking: row.ranking, personID: person.id,
                    personWCAID: own, name: value.name, region: value.countryISO2, attempts: row.attempts,
                    best: row.best, average: row.average, isAdvancing: row.isAdvancing,
                    isAdvancingQuestionable: row.isAdvancingQuestionable,
                    singleRecordTag: row.singleRecordTag, averageRecordTag: row.averageRecordTag)
            }
            regionalEvidence.person(Self.regionalRecords(Self.withResults(mine, metadata: round)),
                personID: person.id, roundID: round.id, observedAt: requestedAt)
        }
        publishContent()
    }
    private func clearPersonal() {
        personalRequest = UUID(); personalLoadedKey = nil; personalEpoch = nil
        ownWCAID = nil; ownPersonID = nil; personalRoundOverrides = [:]
        if !personalResults.isEmpty { personalResults = [] }
    }

    private static func withResults(_ rows: [CompetitionWCALiveResultPreview], metadata: CompetitionWCALiveRound) -> CompetitionWCALiveRound {
        CompetitionWCALiveRound(id: metadata.id, eventID: metadata.eventID, eventName: metadata.eventName,
            roundName: metadata.roundName, number: metadata.number, formatID: metadata.formatID,
            numberOfAttempts: metadata.numberOfAttempts, sortBy: metadata.sortBy, isFinished: metadata.isFinished,
            advancementType: metadata.advancementType, advancementLevel: metadata.advancementLevel,
            isActive: metadata.isActive, isOpen: metadata.isOpen, results: rows)
    }
    private static func personalResult(_ row: CompetitionWCALiveResultPreview, round: CompetitionWCALiveRound) -> CompetitionWCALiveCompetitorResult {
        .init(id: row.id, ranking: row.ranking, isAdvancing: row.isAdvancing, isAdvancingQuestionable: row.isAdvancingQuestionable,
            attempts: row.attempts, best: row.best, average: row.average, singleRecordTag: row.singleRecordTag,
            averageRecordTag: row.averageRecordTag, roundID: round.id, roundName: round.roundName, roundNumber: round.number,
            eventID: round.eventID, eventName: round.eventName, eventRank: nil, formatID: round.formatID ?? "",
            numberOfAttempts: round.numberOfAttempts ?? row.attempts.count, sortBy: round.sortBy ?? "")
    }
    private static func regionalRecords(_ round: CompetitionWCALiveRound) -> [CompetitionWCALiveRecord] {
        round.results.flatMap { row in
            [("single", row.singleRecordTag, row.best), ("average", row.averageRecordTag, row.average)].compactMap { type, raw, value in
                guard let tag = PublishedCompetitionResult.recordBadge(raw) else { return nil }
                return CompetitionWCALiveRecord(id: "wca-live-result:\(row.id):\(type)", tag: tag, type: type, attemptResult: value,
                    eventID: round.eventID, eventName: round.eventName, roundID: round.id, personID: row.personID,
                    personWCAID: row.personWCAID, personName: row.name, countryName: row.region ?? "")
            }
        }
    }
}
