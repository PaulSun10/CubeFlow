import Foundation

/// Official achievements supersede the same provisional achievement, not unrelated records.
nonisolated enum ExploreRecentRecordMerge {
    static func merge(live: [WCARecentRecord], official: [WCAPublicResult]) -> [WCARecentRecord] {
        let rows = official.sorted {
            $0.startDate == $1.startDate ? $0.id > $1.id : $0.startDate > $1.startDate
        }.prefix(60).compactMap { row -> WCARecentRecord? in
            guard let type = row.type, ["single", "average"].contains(type), row.value > 0,
                  let tag = PublishedCompetitionResult.recordBadge(type == "single" ? row.regionalSingleRecord : row.regionalAverageRecord) else { return nil }
            return WCARecentRecord(id: "official-\(row.id)-\(type)", tag: tag, type: type, attemptResult: row.value,
                result: .init(id: String(row.id), person: .init(id: "", wcaId: row.personId,
                    name: row.personName, country: .init(iso2: "", name: row.countryId)),
                    round: .init(id: "", competitionEvent: .init(event: .init(id: row.eventId, name: row.eventId),
                        competition: .init(id: "", wcaId: row.competitionId, name: row.competitionName)))),
                officialResult: row)
        }
        let officialKeys = Set(rows.map(key))
        var seen: Set<String> = []
        return (live.filter { !officialKeys.contains(key($0)) } + rows).filter { seen.insert(key($0)).inserted }
    }

    private static func key(_ record: WCARecentRecord) -> String {
        let event = record.result.round.competitionEvent
        let person = record.result.person.wcaId ?? "live-\(record.result.person.id)"
        return [event.competition.wcaId, event.event.id, person, record.type, String(record.attemptResult)].joined(separator: "|")
    }
}
