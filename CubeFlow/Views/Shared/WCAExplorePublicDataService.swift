import Foundation

nonisolated enum WCAResultType: String, CaseIterable, Identifiable, Codable, Sendable {
    case single, average
    var id: String { rawValue }
}

nonisolated enum WCAPublicGender: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "All"
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

nonisolated enum WCARankingsShow: String, CaseIterable, Identifiable, Codable, Sendable {
    case persons = "100 persons"
    case results = "100 results"
    case byRegion = "by region"
    var id: String { rawValue }
}

nonisolated enum WCARecordsShow: String, CaseIterable, Identifiable, Codable, Sendable {
    case mixed, slim, separate, history
    case mixedHistory = "mixed history"
    var id: String { rawValue }
    var usesHistoryData: Bool { self == .history || self == .mixedHistory }
}

nonisolated struct WCAPublicResult: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let personId: String
    let personName: String
    let countryId: String
    let competitionCountryId: String
    let competitionId: String
    let competitionName: String
    let startDate: String
    let eventId: String
    let attempts: [Int]
    let best: Int
    let average: Int
    let value: Int
    let type: String?
    let regionalSingleRecord: String?
    let regionalAverageRecord: String?

    private enum CodingKeys: String, CodingKey {
        case id, attempts, best, average, value, type
        case personId = "person_id"
        case personName = "person_name"
        case countryId = "country_id"
        case competitionCountryId = "competition_country_id"
        case competitionId = "competition_id"
        case competitionName = "competition_name"
        case startDate = "start_date"
        case eventId = "event_id"
        case regionalSingleRecord = "regional_single_record"
        case regionalAverageRecord = "regional_average_record"
    }
}

nonisolated struct WCARankingsResponse: Codable, Sendable {
    let rankings: [WCAPublicResult]
    let timestamp: String
}

nonisolated struct WCARecordsResponse: Codable, Sendable {
    let records: [String: [WCAPublicResult]]
    let timestamp: String
}

nonisolated struct WCARankingsQuery: Hashable, Sendable {
    let eventID: String
    let type: WCAResultType
    let region: CompetitionRegionFilter
    let gender: WCAPublicGender
    let show: WCARankingsShow
}

nonisolated struct WCARecordsQuery: Hashable, Sendable {
    let region: CompetitionRegionFilter
    let gender: WCAPublicGender
    let show: WCARecordsShow
}

nonisolated struct WCARegionalBest: Identifiable, Hashable, Sendable {
    enum Scope: Hashable, Sendable {
        case world
        case continent(CompetitionContinent)
        case country(code: String, name: String)
    }
    let scope: Scope
    let results: [WCAPublicResult]
    var id: String {
        switch scope {
        case .world: "world"
        case .continent(let continent): "continent-\(continent.id)"
        case .country(let code, _): "country-\(code)"
        }
    }
}

nonisolated struct WCARecordSection: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case event(String)
        case type(WCAResultType)
        case mixedHistory
    }
    let kind: Kind
    let rows: [WCAPublicResult]
    var id: String {
        switch kind {
        case .event(let id): "event-\(id)"
        case .type(let type): "type-\(type.rawValue)"
        case .mixedHistory: "mixed-history"
        }
    }
}

nonisolated struct WCARankedResult: Identifiable, Hashable, Sendable {
    let rank: Int
    let result: WCAPublicResult
    var id: Int { result.id }
}

nonisolated struct WCARecentRecord: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let tag: String
    let type: String
    let attemptResult: Int
    let result: ResultPayload

    struct ResultPayload: Hashable, Codable, Sendable {
        let id: String
        let person: Person
        let round: Round
    }
    struct Person: Hashable, Codable, Sendable {
        let id: String
        let wcaId: String?
        let name: String
        let country: Country
    }
    struct Country: Hashable, Codable, Sendable {
        let iso2: String
        let name: String
    }
    struct Round: Hashable, Codable, Sendable {
        let id: String
        let competitionEvent: CompetitionEvent
    }
    struct CompetitionEvent: Hashable, Codable, Sendable {
        let event: Event
        let competition: Competition
    }
    struct Event: Hashable, Codable, Sendable {
        let id: String
        let name: String
    }
    struct Competition: Hashable, Codable, Sendable {
        let id: String
        let wcaId: String
        let name: String
    }
}

private struct WCARecentRecordsEnvelope: Codable {
    struct DataPayload: Codable { let recentRecords: [WCARecentRecord] }
    let data: DataPayload?
}

enum WCAExplorePublicDataError: Error {
    case invalidURL, requestFailed, invalidResponse
    case httpStatus(Int)
}

enum WCAExplorePublicDataService {
    static func rankedRows(_ rows: [WCAPublicResult]) -> [WCARankedResult] {
        var lastValue: Int?
        var lastRank = 0
        return rows.enumerated().map { offset, result in
            if result.value != lastValue {
                lastRank = offset + 1
                lastValue = result.value
            }
            return WCARankedResult(rank: lastRank, result: result)
        }
    }

    static func fetchRankings(_ query: WCARankingsQuery) async throws -> WCARankingsResponse {
        let data = try await request(rankingsURL(query))
        return try JSONDecoder().decode(WCARankingsResponse.self, from: data)
    }

    static func rankingsURL(_ query: WCARankingsQuery) -> URL? {
        guard var components = URLComponents(string:
            "https://www.worldcubeassociation.org/api/v0/results/rankings/\(query.eventID)/\(query.type.rawValue)") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "region", value: query.show == .byRegion ? "world" : resultsRegionID(query.region)),
            URLQueryItem(name: "show", value: query.show.rawValue),
            URLQueryItem(name: "gender", value: query.gender.rawValue)
        ]
        return components.url
    }

    static func fetchRecords(_ query: WCARecordsQuery) async throws -> WCARecordsResponse {
        let data = try await request(recordsURL(query))
        return try JSONDecoder().decode(WCARecordsResponse.self, from: data)
    }

    static func recordsURL(_ query: WCARecordsQuery) -> URL? {
        guard var components = URLComponents(string: "https://www.worldcubeassociation.org/api/v0/results/records") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "region", value: resultsRegionID(query.region)),
            URLQueryItem(name: "show", value: query.show.usesHistoryData ? "history" : "mixed"),
            URLQueryItem(name: "gender", value: query.gender.rawValue)
        ]
        return components.url
    }

    static func recordsWebsiteURL(_ query: WCARecordsQuery, eventID: String?) -> URL? {
        guard let source = recordsURL(query),
              var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/results/records"
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "show" } + [
            URLQueryItem(name: "show", value: query.show.rawValue),
            URLQueryItem(name: "event_id", value: eventID ?? "all events")
        ]
        return components.url
    }

    static func fetchRecentRecords() async throws -> [WCARecentRecord] {
        let query = """
        query RecentRecords {
          recentRecords {
            id tag type attemptResult
            result {
              id
              person { id wcaId name country { iso2 name } }
              round {
                id
                competitionEvent {
                  event { id name }
                  competition { id wcaId name }
                }
              }
            }
          }
        }
        """
        guard let url = URL(string: "https://live.worldcubeassociation.org/api") else {
            throw WCAExplorePublicDataError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let data = try await requestData(request)
        guard let records = try JSONDecoder().decode(WCARecentRecordsEnvelope.self, from: data).data?.recentRecords else {
            throw WCAExplorePublicDataError.invalidResponse
        }
        return records
    }

    static func regionalBests(
        from rows: [WCAPublicResult],
        selectedRegion: CompetitionRegionFilter,
        countries: [CompetitionRecognizedCountry]
    ) -> [WCARegionalBest] {
        let countryGroups = Dictionary(grouping: rows) { resolvedCountryCode($0.countryId, countries: countries) ?? $0.countryId }
        let all = rowsAtBestValue(rows)
        var output = [WCARegionalBest(scope: .world, results: all)]

        func continentBest(_ continent: CompetitionContinent) -> WCARegionalBest? {
            let matches = countryGroups.filter { continent.countryCodes.contains($0.key) }.flatMap(\.value)
            guard !matches.isEmpty else { return nil }
            return WCARegionalBest(scope: .continent(continent), results: rowsAtBestValue(matches))
        }

        switch selectedRegion {
        case .all:
            output += CompetitionContinent.allCases.compactMap(continentBest)
            output += countryGroups.compactMap { code, countryRows in
                guard let country = countries.first(where: { $0.code == code }) else { return nil }
                return WCARegionalBest(scope: .country(code: code, name: country.wcaName), results: rowsAtBestValue(countryRows))
            }.sorted { ($0.results.first?.value ?? .max) < ($1.results.first?.value ?? .max) }
        case .continent(let continent):
            if let best = continentBest(continent) { output.append(best) }
        case .country(let code):
            if let continent = CompetitionContinent.allCases.first(where: { $0.countryCodes.contains(code) }),
               let best = continentBest(continent) { output.append(best) }
            if let countryRows = countryGroups[code] {
                let name = countries.first(where: { $0.code == code })?.wcaName ?? code
                output.append(WCARegionalBest(scope: .country(code: code, name: name), results: rowsAtBestValue(countryRows)))
            }
        }
        return output.filter { !$0.results.isEmpty }
    }

    static func recordSections(
        _ records: [String: [WCAPublicResult]],
        show: WCARecordsShow,
        eventID: String?
    ) -> [WCARecordSection] {
        let eventOrder = CompetitionEventFilter.selectableCases.map(\.wcaEventID)
        let selectedEvents = eventID.map { [$0] } ?? eventOrder
        switch show {
        case .mixed, .slim, .history:
            return selectedEvents.compactMap { id in
                guard let rows = records[id], !rows.isEmpty else { return nil }
                return WCARecordSection(kind: .event(id), rows: rows)
            }
        case .separate:
            let all = selectedEvents.flatMap { records[$0] ?? [] }
            return WCAResultType.allCases.compactMap { type in
                let rows = all.filter { $0.type == type.rawValue }
                return rows.isEmpty ? nil : WCARecordSection(kind: .type(type), rows: rows)
            }
        case .mixedHistory:
            let rows = selectedEvents.flatMap { records[$0] ?? [] }.sorted {
                if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
                return $0.id < $1.id
            }
            return rows.isEmpty ? [] : [WCARecordSection(kind: .mixedHistory, rows: rows)]
        }
    }

    static func formatResult(_ value: Int, eventID: String) -> String {
        WCAResultFormatter.string(from: value, eventID: eventID)
    }

    static func recentRecordsCandidate(_ records: [WCARecentRecord], language: String) -> [ExploreCandidate] {
        guard !records.isEmpty else { return [] }
        let items = records.map { record -> ExploreItem in
            let level = ExploreResultPresentation.Level(rawValue: record.tag)
            let event = record.result.round.competitionEvent.event
            let eventName = CompetitionEventPresentation.localizedFullName(
                for: event.id,
                languageCode: language,
                fallback: event.name
            )
            let result = formatResult(record.attemptResult, eventID: event.id)
            let type = appLocalizedString("explore.public.sentence_\(record.type)", languageCode: language,
                                          defaultValue: record.type, tableName: "ExplorePublicData")
            let titleFormat = appLocalizedString("explore.public.recent_record_title", languageCode: language,
                                                 defaultValue: "%@ %@ of %@", tableName: "ExplorePublicData")
            let subtitleFormat = appLocalizedString("explore.public.recent_record_person", languageCode: language,
                                                    defaultValue: "%@ from %@", tableName: "ExplorePublicData")
            return ExploreItem(
                id: "recent-record.\(record.id)",
                content: .recentRecord(id: record.id,
                    competitionID: record.result.round.competitionEvent.competition.wcaId,
                    roundID: record.result.round.id,
                    personID: record.result.person.id,
                    personWCAID: record.result.person.wcaId),
                title: String(format: titleFormat, eventName, type, result),
                subtitle: String(
                    format: subtitleFormat,
                    record.result.person.name,
                    CompetitionService.localizedRegionName(
                        for: record.result.person.country.iso2,
                        languageCode: language
                    ) ?? record.result.person.country.name
                ),
                date: nil,
                result: level.map {
                    ExploreResultPresentation(value: result,
                        level: $0,
                        showsValueInBadge: false)
                },
                recordContext: ExploreRecordContext(eventName: eventName,
                    resultType: appLocalizedString("explore.public.\(record.type)", languageCode: language,
                        defaultValue: record.type.capitalized, tableName: "ExplorePublicData"),
                    personName: record.result.person.name,
                    countryName: CompetitionService.localizedRegionName(for: record.result.person.country.iso2,
                        languageCode: language) ?? record.result.person.country.name,
                    competitionName: record.result.round.competitionEvent.competition.name)
            )
        }
        guard !items.isEmpty else { return [] }
        var candidates = [ExploreCandidate(id: "records.recent", titleKey: "explore.public.recent_records",
            items: items, presentation: .compactList, importance: 55, seeAll: .records,
            titleTable: "ExplorePublicData")]
        if let world = records.first(where: { $0.tag == "WR" }),
           let item = items.first(where: { $0.id == "recent-record.\(world.id)" }) {
            candidates.append(ExploreCandidate(id: "records.recent-world", titleKey: "explore.public.world_record",
                items: [item], presentation: .hero, heroEligibility: .worldRecord, importance: 85,
                seeAll: .records, titleTable: "ExplorePublicData"))
        }
        return candidates
    }

    private static func request(_ url: URL?) async throws -> Data {
        guard let url else { throw WCAExplorePublicDataError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CubeFlow iOS", forHTTPHeaderField: "User-Agent")
        return try await requestData(request)
    }

    private static func requestData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return data
    }

    static func validateResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw WCAExplorePublicDataError.invalidResponse }
        guard 200 ..< 300 ~= response.statusCode else { throw WCAExplorePublicDataError.httpStatus(response.statusCode) }
    }

    private static func resultsRegionID(_ region: CompetitionRegionFilter) -> String {
        switch region {
        case .all: "world"
        case .continent(let continent): continent.wcaAPIID
        case .country(let code): code
        }
    }

    private static func rowsAtBestValue(_ rows: [WCAPublicResult]) -> [WCAPublicResult] {
        guard let best = rows.map(\.value).min() else { return [] }
        return rows.filter { $0.value == best }.sorted {
            if $0.countryId != $1.countryId { return $0.countryId < $1.countryId }
            if $0.personName != $1.personName { return $0.personName < $1.personName }
            return $0.id < $1.id
        }
    }

    private static func resolvedCountryCode(_ name: String, countries: [CompetitionRecognizedCountry]) -> String? {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return countries.first { country in
            let candidates = [country.wcaName, country.wcaName.replacingOccurrences(of: ", China", with: "")]
            return candidates.contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized }
        }?.code
    }

}

actor WCAExplorePublicDataCache {
    static let shared = WCAExplorePublicDataCache()

    struct Cached<Value: Codable & Sendable>: Codable, Sendable {
        let value: Value
        let fetchedAt: Date
    }

    func load<Value: Codable & Sendable>(_ type: Value.Type, key: String) -> Cached<Value>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(Cached<Value>.self, from: data)
    }

    func save<Value: Codable & Sendable>(_ value: Value, key: String, now: Date = Date()) {
        let destination = url(for: key)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Cached(value: value, fetchedAt: now)) else { return }
        try? data.write(to: destination, options: .atomic)
    }

    private func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CubeFlowExplorePublicData", isDirectory: true)
        return directory.appendingPathComponent(String(safe) + ".json")
    }
}
