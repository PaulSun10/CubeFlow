import Foundation

enum CubingChinaLivePresentation {
    static func roundName(_ round: CubingChinaLiveRound, rounds: [CubingChinaLiveRound], language: String) -> String {
        let final = rounds.filter { $0.eventId == round.eventId }.map(\.roundNumber).max()
        return PublishedCompetitionStrings.round(round.roundNumber == final ? "f" : String(round.roundNumber), language: language)
    }

    static func options(_ rounds: [CubingChinaLiveRound], snapshot: CubingChinaLiveSnapshot?, language: String) -> [CompetitionLiveRoundOption] {
        rounds.map { round in
            let results = snapshot?.round.id == round.id ? snapshot?.results : nil
            return CompetitionLiveRoundOption(id: round.key.selectionID, eventID: round.eventId,
                roundID: String(round.roundNumber),
                eventName: CubingChinaEventDisplay.name(round.eventId, language: language),
                roundName: roundName(round, rounds: rounds, language: language), statusText: nil,
                recordedCount: results?.filter { $0.attempts.contains(where: { $0 != 0 }) }.count ?? 0,
                totalCount: results?.count ?? 0, formatID: round.round.format)
        }
    }

    static func content(_ bootstrap: CubingChinaLiveBootstrap, language: String) -> CompetitionLiveContent {
        CompetitionLiveContent(competitionID: bootstrap.competitionID.rawValue, sourceType: "modern-rest-sse",
            roundOptions: options(bootstrap.rounds, snapshot: nil, language: language), filterOptions: [],
            defaultEventID: bootstrap.defaultRound.eventId, defaultRoundID: String(bootstrap.defaultRound.roundNumber),
            defaultFilterValue: "all", staticMessages: [], sumOfRanksURL: nil, podiumsURL: nil,
            sumOfRanksContent: nil, podiumSections: [], modern: bootstrap)
    }

    static func preview(_ value: CubingChinaLiveResult, language: String,
                        advancement: CompetitionAdvancement? = nil) -> CompetitionWCALiveResultPreview {
        let competitor = value.competitor
        let region = competitor?.regionIso2.flatMap { appLocale(for: language).localizedString(forRegionCode: $0) ?? $0 }
        let local = competitor?.localName.flatMap { $0.isEmpty ? nil : $0 }
        return CompetitionWCALiveResultPreview(id: "ccc-result:\(value.id.rawValue)", ranking: value.position,
            personID: nil, personWCAID: competitor?.wcaId,
            name: language.hasPrefix("zh") ? local ?? competitor?.name ?? "" : competitor?.name ?? "",
            region: region, attempts: value.attempts, best: value.best, average: value.average,
            isAdvancing: advancement == nil ? nil : true, isAdvancingQuestionable: advancement?.questionable,
            singleRecordTag: value.singleIndicator,
            averageRecordTag: value.averageIndicator)
    }

    static func round(_ snapshot: CubingChinaLiveSnapshot, rounds: [CubingChinaLiveRound], language: String,
                      nextParticipants: Set<CubingChinaLiveID<CubingChinaIDKind.User>>? = nil,
                      advancementStates: [String: CompetitionAdvancement]? = nil) -> CompetitionWCALiveRound {
        let value = snapshot.round
        let states = advancementStates ?? advancement(snapshot, rounds: rounds, nextParticipants: nextParticipants)
        return CompetitionWCALiveRound(id: "ccc-round:\(value.id.rawValue)", eventID: value.eventId,
            eventName: CubingChinaEventDisplay.name(value.eventId, language: language),
            roundName: roundName(value, rounds: rounds, language: language), number: value.roundNumber,
            formatID: value.round.format, numberOfAttempts: value.attemptCount,
            sortBy: ["a", "m"].contains(value.round.format) ? "average" : "best", isFinished: value.isFinished,
            advancementType: value.round.advancementCondition?.type, advancementLevel: value.round.advancementCondition?.level,
            isActive: value.status == "live", isOpen: value.status == "open",
            results: snapshot.rankedResults.map { preview($0, language: language, advancement: states["ccc-result:\($0.id.rawValue)"]) })
    }

    static func advancement(_ snapshot: CubingChinaLiveSnapshot, rounds: [CubingChinaLiveRound],
                            nextParticipants: Set<CubingChinaLiveID<CubingChinaIDKind.User>>? = nil) -> [String: CompetitionAdvancement] {
        guard rounds.contains(snapshot.round) else { return [:] }
        let later = rounds.filter { $0.eventId == snapshot.round.eventId && $0.roundNumber > snapshot.round.roundNumber }
        if let next = later.min(by: { $0.roundNumber < $1.roundNumber }),
           ["open", "live", "finished"].contains(next.status) {
            guard next.roundNumber == snapshot.round.roundNumber + 1, let nextParticipants else { return [:] }
            return Dictionary(uniqueKeysWithValues: snapshot.results.filter { nextParticipants.contains($0.userId) }
                .map { ("ccc-result:\($0.id.rawValue)", .confirmed) })
        }
        return CompetitionAdvancementCalculation.states(snapshot, isFinal: later.isEmpty && snapshot.round.round.advancementCondition == nil)
    }

    static func competitor(_ values: [CubingChinaLiveResult], rounds: [CubingChinaLiveRound], language: String,
                           knownAdvancement: [String: CompetitionAdvancement] = [:]) -> CompetitionWCALiveCompetitorContent? {
        guard let first = values.first, let person = first.competitor else { return nil }
        let results = values.compactMap { value -> CompetitionWCALiveCompetitorResult? in
            guard let round = rounds.first(where: { value.belongs(to: $0) }) else { return nil }
            let later = rounds.filter { $0.eventId == round.eventId && $0.roundNumber > round.roundNumber }
            let next = later.first { $0.roundNumber == round.roundNumber + 1 }
            let participated = next.map { next in values.contains { $0.userId == value.userId && $0.belongs(to: next)
                && $0.attempts.contains(where: { $0 != 0 }) } } ?? false
            let podium = later.isEmpty && round.round.advancementCondition == nil && round.isFinished
                && (value.position.map { $0 <= 3 } ?? false) && value.best > 0
            let state: CompetitionAdvancement? = participated || podium ? .confirmed : knownAdvancement["ccc-result:\(value.id.rawValue)"]
            return CompetitionWCALiveCompetitorResult(id: "ccc-result:\(value.id.rawValue)", ranking: value.position,
                isAdvancing: state == nil ? nil : true, isAdvancingQuestionable: state?.questionable,
                attempts: value.attempts, best: value.best, average: value.average,
                singleRecordTag: value.singleIndicator,
                averageRecordTag: value.averageIndicator,
                roundID: "ccc-round:\(round.id.rawValue)",
                roundName: roundName(round, rounds: rounds, language: language), roundNumber: round.roundNumber,
                eventID: round.eventId, eventName: CubingChinaEventDisplay.name(round.eventId, language: language),
                eventRank: nil, formatID: round.round.format, numberOfAttempts: round.attemptCount,
                sortBy: ["a", "m"].contains(round.round.format) ? "average" : "best")
        }
        guard !results.isEmpty else { return nil }
        return CompetitionWCALiveCompetitorContent(id: "ccc-user:\(person.id.rawValue)", name: preview(first, language: language).name,
            wcaID: person.wcaId, countryISO2: person.regionIso2, results: results)
    }
}

extension CompetitionLiveContent {
    func targetRound(for target: CompetitionWCALiveResultDeepLink) -> CompetitionLiveRoundOption? {
        guard modern != nil else { return target.cubingChinaRound(in: roundOptions) }
        guard let event = target.eventID, let number = target.roundNumber else { return nil }
        return roundOptions.first { $0.eventID == event && $0.roundID == String(number) }
    }
}
