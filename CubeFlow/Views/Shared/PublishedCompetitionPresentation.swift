import Foundation

/// Presentation adapters only: official rows stay authoritative and never acquire Live IDs/status.
enum PublishedCompetitionPresentation {
    static func preview(_ row: PublishedCompetitionResult, language: String) -> CompetitionWCALiveResultPreview {
        CompetitionWCALiveResultPreview(id: "published-\(row.id)", ranking: row.rank,
            personID: nil, personWCAID: row.wcaID, name: row.name,
            region: appLocale(for: language).localizedString(forRegionCode: row.countryISO2) ?? row.countryISO2,
            attempts: row.performedAttempts, best: row.best, average: row.average,
            isAdvancing: nil, isAdvancingQuestionable: nil, singleRecordTag: row.singleBadge, averageRecordTag: row.averageBadge)
    }

    static func attemptCount(_ format: String) -> Int {
        switch format { case "1": 1; case "2": 2; case "3", "m": 3; default: 5 }
    }

    static func round(_ round: PublishedCompetitionRound, language: String, data: PublishedCompetitionData? = nil) -> CompetitionWCALiveRound {
        let format = round.results.first?.formatID ?? "a"
        let advancing = data?.confirmedAdvancingPeople(from: round) ?? []
        return CompetitionWCALiveRound(id: "published-\(round.id)", eventID: round.eventID,
            eventName: CompetitionEventPresentation.localizedFullName(for: round.eventID, languageCode: language),
            roundName: PublishedCompetitionStrings.round(round.typeID, language: language),
            number: nil, formatID: format, numberOfAttempts: attemptCount(format),
            sortBy: ["a", "m"].contains(format) ? "average" : "best", isFinished: true,
            advancementType: nil, advancementLevel: nil, isActive: false, isOpen: false,
            results: round.results.map { row in
                let value = preview(row, language: language)
                guard advancing.contains(row.wcaID) || (round.isFinal && row.rank <= 3 && row.best > 0) else { return value }
                return CompetitionWCALiveResultPreview(id: value.id, ranking: value.ranking,
                    personID: nil, personWCAID: value.personWCAID, name: value.name, region: value.region,
                    attempts: value.attempts, best: value.best, average: value.average,
                    isAdvancing: true, isAdvancingQuestionable: nil,
                    singleRecordTag: value.singleRecordTag, averageRecordTag: value.averageRecordTag)
            })
    }

    static func competitor(_ id: String, data: PublishedCompetitionData, language: String) -> CompetitionWCALiveCompetitorContent? {
        let rows = data.results(for: id)
        guard let first = rows.first else { return nil }
        let results = rows.map { row in
            let eventRounds = data.rounds(for: row.eventID)
            let round = eventRounds.first { $0.id == row.roundKey }
            let confirmed = round.map { data.confirmedAdvancingPeople(from: $0).contains(row.wcaID)
                || ($0.isFinal && row.rank <= 3 && row.best > 0) } ?? false
            return CompetitionWCALiveCompetitorResult(id: "published-\(row.id)", ranking: row.rank,
                isAdvancing: confirmed ? true : nil, isAdvancingQuestionable: nil, attempts: row.performedAttempts,
                best: row.best, average: row.average, singleRecordTag: row.singleBadge, averageRecordTag: row.averageBadge,
                roundID: "published-\(row.roundKey)", roundName: PublishedCompetitionStrings.round(row.roundTypeID, language: language),
                roundNumber: eventRounds.firstIndex { $0.id == row.roundKey }, eventID: row.eventID,
                eventName: CompetitionEventPresentation.localizedFullName(for: row.eventID, languageCode: language),
                eventRank: data.eventIDs.firstIndex(of: row.eventID), formatID: row.formatID,
                numberOfAttempts: attemptCount(row.formatID), sortBy: row.usesAverage ? "average" : "best")
        }
        return CompetitionWCALiveCompetitorContent(id: id, name: first.name, wcaID: id,
            countryISO2: first.countryISO2, results: results)
    }
}
