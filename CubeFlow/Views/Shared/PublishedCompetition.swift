import Foundation
import Combine

/// Official published results, deliberately separate from provisional Live rows.
nonisolated struct PublishedCompetitionResult: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let competitionID: String
    let eventID: String
    let roundID: Int?
    let roundTypeID: String
    let formatID: String
    let rank: Int
    let name: String
    let wcaID: String
    let countryISO2: String
    let best: Int
    let average: Int
    let attempts: [Int]
    let singleRecord: String?
    let averageRecord: String?
    // Presentation evidence joined from the authoritative public person page,
    // not invented fields in the official competition JSON contract.
    var personalSingleRecord: String? = nil
    var personalAverageRecord: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, best, average, attempts
        case competitionID = "competition_id", eventID = "event_id", roundID = "round_id"
        case roundTypeID = "round_type_id", formatID = "format_id", rank = "pos"
        case wcaID = "wca_id", countryISO2 = "country_iso2"
        case singleRecord = "regional_single_record", averageRecord = "regional_average_record"
    }

    var roundKey: String { "\(eventID)|\(roundID.map(String.init) ?? roundTypeID)" }
    var usesAverage: Bool { ["a", "m"].contains(formatID) }
    var showsAverage: Bool { usesAverage || average != 0 }
    var performedAttempts: [Int] {
        guard let last = attempts.lastIndex(where: { $0 != 0 }) else { return [] }
        return Array(attempts[...last])
    }
    var hasSuccessfulResult: Bool { best > 0 && (!usesAverage || average > 0) }
    var singleBadge: String? { CubingLiveRecordIndicators.display(regional: singleRecord, personal: personalSingleRecord) }
    var averageBadge: String? { CubingLiveRecordIndicators.display(regional: averageRecord, personal: personalAverageRecord) }
    var highestBadge: String? { Self.highestBadge([singleBadge, averageBadge]) }

    static func highestBadge(_ tags: [String?]) -> String? {
        let normalized = tags.compactMap(recordBadge)
        return ["WR", "CR", "NR"].first { normalized.contains($0) }
    }

    static func recordBadge(_ raw: String?) -> String? {
        switch raw?.uppercased() {
        case "WR": return "WR"
        case "CR": return "CR"
        case "NR": return "NR"
        case "AFR", "ASR", "ER", "NAR", "OCR", "SAR",
             "AF", "AS", "NA", "OC", "SA": return "CR"
        default: return nil
        }
    }

    func formatted(_ value: Int, average: Bool = false) -> String {
        WCAResultFormatter.string(from: value, eventID: eventID,
            resultType: average ? "average" : "single", zeroRepresentation: "\u{2014}")
    }
}

nonisolated struct PublishedCompetitionResultDeepLink: Hashable, Sendable {
    let competitionID: String
    let resultID: Int
    let eventID: String

    func result(in data: PublishedCompetitionData) -> PublishedCompetitionResult? {
        guard data.competitionID == competitionID else { return nil }
        return data.results.first {
            $0.id == resultID && $0.eventID == eventID && $0.competitionID == competitionID
        }
    }
}

nonisolated struct PublishedCompetitionRound: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let typeID: String
    let results: [PublishedCompetitionResult]
    var isFinal: Bool { ["f", "c"].contains(typeID) }
    var podium: [PublishedCompetitionResult] {
        guard isFinal else { return [] }
        return results.filter { (1...3).contains($0.rank) && $0.hasSuccessfulResult }
    }
    var champions: [PublishedCompetitionResult] { podium.filter { $0.rank == 1 } }
    static func order(_ type: String) -> Int {
        ["0": 0, "h": 0, "1": 1, "d": 1, "2": 2, "e": 2, "3": 3, "g": 3,
         "b": 4, "f": 5, "c": 5][type] ?? 4
    }
}

nonisolated struct PublishedCompetitionPerson: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let countryISO2: String
}

nonisolated struct PublishedCompetitionData: Sendable {
    let competitionID: String
    let results: [PublishedCompetitionResult]
    let eventIDs: [String]
    let rounds: [PublishedCompetitionRound]
    let people: [PublishedCompetitionPerson]
    private let resultsByPerson: [String: [PublishedCompetitionResult]]
    private let roundsByEvent: [String: [PublishedCompetitionRound]]
    let eventRecordTags: [String: String]
    let roundRecordTags: [String: String]

    func selectorRecordTags(ownWCAID: String?) -> (events: [String: String], rounds: [String: String]) {
        var events = eventRecordTags, rounds = roundRecordTags
        guard let own = CompetitionPersonalIdentity.canonical(ownWCAID) else { return (events, rounds) }
        for row in results where CompetitionPersonalIdentity.matches(signedInWCAID: own, competitorWCAID: row.wcaID)
            && (row.singleBadge == "PR" || row.averageBadge == "PR") {
            if events[row.eventID] == nil { events[row.eventID] = "PR" }
            if rounds[row.roundKey] == nil { rounds[row.roundKey] = "PR" }
        }
        return (events, rounds)
    }

    init(competitionID: String, results: [PublishedCompetitionResult], eventOrder: [String] = []) {
        self.competitionID = competitionID
        self.results = results
        let events = Set(results.map(\.eventID))
        let orderedEvents = eventOrder.filter { events.contains($0) } + events.subtracting(eventOrder).sorted()
        eventIDs = orderedEvents
        let grouped = Dictionary(grouping: results, by: \.roundKey)
        let orderedRounds = grouped.compactMap { key, rows -> PublishedCompetitionRound? in
            guard let first = rows.first else { return nil }
            return PublishedCompetitionRound(id: key, eventID: first.eventID, typeID: first.roundTypeID,
                results: rows.sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank })
        }.sorted {
            let left = orderedEvents.firstIndex(of: $0.eventID) ?? Int.max
            let right = orderedEvents.firstIndex(of: $1.eventID) ?? Int.max
            return left == right ? PublishedCompetitionRound.order($0.typeID) < PublishedCompetitionRound.order($1.typeID) : left < right
        }
        rounds = orderedRounds
        roundsByEvent = Dictionary(grouping: orderedRounds, by: \.eventID)
        eventRecordTags = Dictionary(grouping: results, by: \.eventID).compactMapValues {
            PublishedCompetitionResult.highestBadge($0.map(\.highestBadge))
        }
        roundRecordTags = grouped.compactMapValues {
            PublishedCompetitionResult.highestBadge($0.map(\.highestBadge))
        }
        let byPerson = Dictionary(grouping: results, by: \.wcaID)
        resultsByPerson = byPerson
        people = byPerson.compactMap { id, rows in
            guard let first = rows.first else { return nil }
            return PublishedCompetitionPerson(id: id, name: first.name, countryISO2: first.countryISO2)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var isPublished: Bool { !results.isEmpty }
    var finals: [PublishedCompetitionRound] { rounds.filter(\.isFinal) }
    func rounds(for eventID: String) -> [PublishedCompetitionRound] { roundsByEvent[eventID] ?? [] }
    func confirmedAdvancingPeople(from round: PublishedCompetitionRound) -> Set<String> {
        guard ["0", "h", "1", "d", "2", "e", "3", "g"].contains(round.typeID),
              let next = rounds(for: round.eventID).first(where: {
                  $0.typeID != "b" && PublishedCompetitionRound.order($0.typeID) > PublishedCompetitionRound.order(round.typeID)
              }) else { return [] }
        // Participation in the next official round proves advancement. Absence does not
        // prove elimination: qualified competitors may withdraw before recording results.
        return Set(next.results.map(\.wcaID))
    }
    func results(for personID: String) -> [PublishedCompetitionResult] { resultsByPerson[personID] ?? [] }
    func people(query: String, currentWCAID: String?) -> [PublishedCompetitionPerson] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = people.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
        guard let currentWCAID, let index = matches.firstIndex(where: { $0.id == currentWCAID }) else { return matches }
        var ordered = matches
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}

nonisolated struct PublishedCompetitionScramble: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let competitionID: String
    let eventID: String
    let roundID: Int?
    let roundTypeID: String
    let groupID: String
    let isExtra: Bool
    let number: Int
    let scramble: String
    enum CodingKeys: String, CodingKey {
        case id, scramble
        case competitionID = "competition_id", eventID = "event_id", roundID = "round_id"
        case roundTypeID = "round_type_id", groupID = "group_id", isExtra = "is_extra", number = "scramble_num"
    }
    var roundKey: String { "\(eventID)|\(roundID.map(String.init) ?? roundTypeID)" }
    var setKey: String { "\(roundKey)|\(groupID)" }
    var displayNumber: String { isExtra ? "E\(number)" : String(number) }
    var puzzleKey: String? {
        switch eventID {
        case "222": return "222"
        case "333", "333oh", "333bf": return "333"
        case "444", "444bf": return "444"
        case "555", "555bf": return "555"
        case "666", "777": return eventID
        case "minx": return "megaminx"
        case "pyram": return "pyraminx"
        case "skewb": return "skewb"
        case "sq1": return "squareone"
        case "clock": return "clk"
        case "fto": return "fto"
        default: return nil // FMC/MBLD need their official multi-part context, not a guessed diagram.
        }
    }
}

nonisolated struct PublishedScrambleSet: Identifiable, Sendable {
    let id: String
    let eventID: String
    let roundKey: String
    let roundTypeID: String
    let groupID: String
    let scrambles: [PublishedCompetitionScramble]
    static func grouped(_ rows: [PublishedCompetitionScramble]) -> [Self] {
        Dictionary(grouping: rows, by: \.setKey).compactMap { key, values in
            guard let first = values.first else { return nil }
            return Self(id: key, eventID: first.eventID, roundKey: first.roundKey,
                roundTypeID: first.roundTypeID, groupID: first.groupID,
                scrambles: values.sorted {
                    if $0.isExtra != $1.isExtra { return !$0.isExtra }
                    return $0.number == $1.number ? $0.id < $1.id : $0.number < $1.number
                })
        }.sorted {
            if $0.roundKey != $1.roundKey { return $0.roundKey < $1.roundKey }
            return $0.groupID.localizedStandardCompare($1.groupID) == .orderedAscending
        }
    }
}

/// Resolve each selection level once. Never call derived getters inside filters/sorts.
nonisolated struct PublishedScrambleSelection: Sendable {
    let events: [String]
    let eventID: String
    let roundOptions: [(id: String, type: String)]
    let roundID: String
    let groups: [String]
    let currentSet: PublishedScrambleSet?

    init(sets: [PublishedScrambleSet], eventOrder: [String], event: String, round: String, group: String) {
        let available = Set(sets.map(\.eventID))
        events = eventOrder.filter { available.contains($0) } + available.subtracting(eventOrder).sorted()
        let resolvedEvent = available.contains(event) ? event : events.first ?? ""
        eventID = resolvedEvent
        let eventSets = sets.filter { $0.eventID == resolvedEvent }
        let byRound = Dictionary(grouping: eventSets, by: \.roundKey)
        let options = byRound.compactMap { key, values -> (id: String, type: String)? in
            guard let first = values.first else { return nil }
            return (key, first.roundTypeID)
        }.sorted {
            let left = PublishedCompetitionRound.order($0.type), right = PublishedCompetitionRound.order($1.type)
            return left == right ? $0.id < $1.id : left < right
        }
        roundOptions = options
        let resolvedRound = byRound[round] != nil ? round : options.first?.id ?? ""
        roundID = resolvedRound
        let roundSets = byRound[resolvedRound] ?? []
        groups = roundSets.map(\.groupID)
        currentSet = roundSets.first { $0.groupID == group } ?? roundSets.first
    }
}

nonisolated struct PublishedCompetitionLoad: Sendable {
    let data: PublishedCompetitionData
    let metrics: PublishedCompetitionMetrics
    var isStale: Bool = false
}

nonisolated struct PublishedCachedScrambles: Sendable {
    let sets: [PublishedScrambleSet]
    let isStale: Bool
}

nonisolated struct PublishedCompetitionMetrics: Sendable {
    let resource: String
    let competitionID: String
    let httpStatus: Int?
    let bytes: Int
    let networkMS: Double
    let decodeMS: Double
    let modelMS: Double
    let cacheHit: Bool
}

nonisolated enum PublishedCompetitionClock {
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func milliseconds(since start: UInt64) -> Double { Double(now() - start) / 1_000_000 }
}

/// Bounded canonical snapshots and shared in-flight requests. Work stays off the main actor.
actor PublishedCompetitionService {
    static let shared = PublishedCompetitionService(cache: .shared)
    private let session: URLSession
    private let cache: CompetitionSnapshotCache?
    private let now: @Sendable () -> Date
    private var resultCache: [String: (Date, PublishedCompetitionData)] = [:]
    private var scrambleCache: [String: (Date, [PublishedScrambleSet])] = [:]
    private var resultCosts: [String: Int] = [:]
    private var scrambleCosts: [String: Int] = [:]
    private let resultRequests = CompetitionRequestPool<PublishedCompetitionLoad>()
    private let scrambleRequests = CompetitionRequestPool<[PublishedScrambleSet]>()
    private let responseRequests = CompetitionRequestPool<Response>()
    private var cacheGeneration = 0
    private var responseTokens: [String: UUID] = [:]
    private var responseOrder: [String] = []
    private struct Response: Sendable {
        let bytes: Int
        let bodyBytes: Int
        let results: [PublishedCompetitionResult]
        let scrambles: [PublishedCompetitionScramble]
        let status: Int
        let networkMS: Double
        let decodeMS: Double
        let validatedAt: Date
        let token: UUID
    }

    init(session: URLSession = .shared, cache: CompetitionSnapshotCache? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session; self.cache = cache; self.now = now
    }

    private func snapshotKey(_ id: String, resource: String) -> CompetitionSnapshotKey {
        .init(provider: "wca-official", competition: id, resource: resource, schema: 1)
    }

    /// A stale positive official snapshot is useful offline; an old empty response
    /// must not permanently classify a newly published competition as unpublished.
    func cachedResults(competitionID: String, eventOrder: [String]) async -> PublishedCompetitionLoad? {
        let run = cacheGeneration
        let token = responseTokens["results|" + competitionID]
        let key = competitionID + "|" + eventOrder.joined(separator: ",")
        if resultCache[key] == nil, let cache, let entry = await cache.entry(for: snapshotKey(competitionID, resource: "results")) {
            guard run == cacheGeneration, responseTokens["results|" + competitionID] == token else { return nil }
            if let rows = try? Self.decodeResults(entry.body, competitionID: competitionID) {
                resultCache[key] = (entry.validatedAt, PublishedCompetitionData(competitionID: competitionID, results: rows, eventOrder: eventOrder))
                resultCosts[key] = entry.body.count; trimModels(protectingResult: key)
            } else { await cache.remove(snapshotKey(competitionID, resource: "results")) }
        }
        guard let entry = resultCache[key], now().timeIntervalSince(entry.0) >= -60,
              now().timeIntervalSince(entry.0) <= CompetitionSnapshotCache.retention,
              entry.1.isPublished || now().timeIntervalSince(entry.0) < 60 else { return nil }
        return PublishedCompetitionLoad(data: entry.1, metrics: PublishedCompetitionMetrics(resource: "results", competitionID: competitionID,
            httpStatus: nil, bytes: 0, networkMS: 0, decodeMS: 0, modelMS: 0, cacheHit: true),
            isStale: now().timeIntervalSince(entry.0) >= 3600)
    }

    func cachedScrambles(competitionID: String) async -> [PublishedScrambleSet]? {
        await cachedScrambleSnapshot(competitionID: competitionID)?.sets
    }

    func cachedScrambleSnapshot(competitionID: String) async -> PublishedCachedScrambles? {
        let run = cacheGeneration
        let token = responseTokens["scrambles|" + competitionID]
        if scrambleCache[competitionID] == nil, let cache,
           let entry = await cache.entry(for: snapshotKey(competitionID, resource: "scrambles")) {
            guard run == cacheGeneration, responseTokens["scrambles|" + competitionID] == token else { return nil }
            if let rows = try? Self.decodeScrambles(entry.body, competitionID: competitionID) {
                scrambleCache[competitionID] = (entry.validatedAt, PublishedScrambleSet.grouped(rows))
                scrambleCosts[competitionID] = entry.body.count; trimModels(protectingScrambles: competitionID)
            } else { await cache.remove(snapshotKey(competitionID, resource: "scrambles")) }
        }
        guard let entry = scrambleCache[competitionID], now().timeIntervalSince(entry.0) >= -60,
              now().timeIntervalSince(entry.0) <= CompetitionSnapshotCache.retention,
              !entry.1.isEmpty || now().timeIntervalSince(entry.0) < 60 else { return nil }
        return PublishedCachedScrambles(sets: entry.1, isStale: now().timeIntervalSince(entry.0) >= 3600)
    }

    private func trimModels(protectingResult: String? = nil, protectingScrambles: String? = nil) {
        resultCosts = resultCosts.filter { resultCache[$0.key] != nil }
        scrambleCosts = scrambleCosts.filter { scrambleCache[$0.key] != nil }
        while resultCache.count > 12 || resultCosts.values.reduce(0, +) > 16 * 1024 * 1024 {
            guard let oldest = resultCache.filter({ $0.key != protectingResult }).min(by: { $0.value.0 < $1.value.0 }) else { break }
            resultCache[oldest.key] = nil; resultCosts[oldest.key] = nil
        }
        while scrambleCache.count > 8 || scrambleCosts.values.reduce(0, +) > 16 * 1024 * 1024 {
            guard let oldest = scrambleCache.filter({ $0.key != protectingScrambles }).min(by: { $0.value.0 < $1.value.0 }) else { break }
            scrambleCache[oldest.key] = nil; scrambleCosts[oldest.key] = nil
        }
    }

    func clear() async {
        cacheGeneration += 1
        responseTokens = [:]; responseOrder = []
        await resultRequests.cancelAll(); await scrambleRequests.cancelAll(); await responseRequests.cancelAll()
        resultCache = [:]; scrambleCache = [:]
        resultCosts = [:]; scrambleCosts = [:]
        await cache?.clear()
    }

    func results(competitionID: String, eventOrder: [String], refresh: Bool = false) async throws -> PublishedCompetitionData {
        try await resultSnapshot(competitionID: competitionID, eventOrder: eventOrder, refresh: refresh).data
    }

    func resultSnapshot(competitionID: String, eventOrder: [String], refresh: Bool = false) async throws -> PublishedCompetitionLoad {
        let key = competitionID + "|" + eventOrder.joined(separator: ",")
        _ = await cachedResults(competitionID: competitionID, eventOrder: eventOrder)
        if !refresh, let cached = resultCache[key], now().timeIntervalSince(cached.0) >= -60,
           now().timeIntervalSince(cached.0) < (cached.1.isPublished ? 3600 : 60) {
            return PublishedCompetitionLoad(data: cached.1, metrics: PublishedCompetitionMetrics(resource: "results", competitionID: competitionID,
                httpStatus: nil, bytes: 0, networkMS: 0, decodeMS: 0, modelMS: 0, cacheHit: true))
        }
        return try await resultRequests.value(key: key) {
            try await self.loadResults(competitionID: competitionID, eventOrder: eventOrder, key: key)
        }
    }

    private func loadResults(competitionID: String, eventOrder: [String], key: String) async throws -> PublishedCompetitionLoad {
        let response = try await request(competitionID, resource: "results")
        guard responseTokens["results|" + competitionID] == response.token else { throw CancellationError() }
        let rows = response.results
        let decodeMS = response.decodeMS
        let modelStart = PublishedCompetitionClock.now()
        let model = PublishedCompetitionData(competitionID: competitionID, results: rows, eventOrder: eventOrder)
        let loaded = PublishedCompetitionLoad(data: model, metrics: PublishedCompetitionMetrics(resource: "results", competitionID: competitionID,
            httpStatus: response.status, bytes: response.bytes, networkMS: response.networkMS, decodeMS: decodeMS,
            modelMS: PublishedCompetitionClock.milliseconds(since: modelStart), cacheHit: false))
        try Task.checkCancellation()
        if response.bodyBytes <= 16 * 1024 * 1024 {
            resultCache[key] = (response.validatedAt, loaded.data); resultCosts[key] = response.bodyBytes
            trimModels(protectingResult: key)
        }
        return loaded
    }

    func scrambles(competitionID: String, refresh: Bool = false) async throws -> [PublishedScrambleSet] {
        _ = await cachedScrambles(competitionID: competitionID)
        if !refresh, let cached = scrambleCache[competitionID], now().timeIntervalSince(cached.0) >= -60,
           now().timeIntervalSince(cached.0) < (cached.1.isEmpty ? 60 : 3600) { return cached.1 }
        return try await scrambleRequests.value(key: competitionID) { try await self.loadScrambles(competitionID: competitionID) }
    }

    private func loadScrambles(competitionID: String) async throws -> [PublishedScrambleSet] {
        let response = try await request(competitionID, resource: "scrambles")
        guard responseTokens["scrambles|" + competitionID] == response.token else { throw CancellationError() }
        let decoded = response.scrambles
        let decodeMS = response.decodeMS
        let modelStart = PublishedCompetitionClock.now()
        let grouped = PublishedScrambleSet.grouped(decoded)
        try Task.checkCancellation()
        if response.bodyBytes <= 16 * 1024 * 1024 {
            scrambleCache[competitionID] = (response.validatedAt, grouped); scrambleCosts[competitionID] = response.bodyBytes
            trimModels(protectingScrambles: competitionID)
        }
        Self.log(PublishedCompetitionMetrics(resource: "scrambles", competitionID: competitionID, httpStatus: response.status,
            bytes: response.bytes, networkMS: response.networkMS, decodeMS: decodeMS,
            modelMS: PublishedCompetitionClock.milliseconds(since: modelStart), cacheHit: false))
        return grouped
    }

    private func request(_ id: String, resource: String) async throws -> Response {
        try await responseRequests.value(key: "wca-official|\(id)|\(resource)|v1") {
            try await self.fetchResponse(id, resource: resource)
        }
    }

    private func fetchResponse(_ id: String, resource: String) async throws -> Response {
        let run = cacheGeneration
        guard Self.validCompetitionID(id), let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(id)/\(resource)") else {
            throw CompetitionServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60 // Championships can return several MB of published rows.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = snapshotKey(id, resource: resource)
        let previous = await cache?.entry(for: key)
        if let etag = previous?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = previous?.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let started = PublishedCompetitionClock.now()
        let (data, response) = try await session.data(for: request)
        let networkMS = PublishedCompetitionClock.milliseconds(since: started)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) || (http.statusCode == 304 && previous != nil) else {
            throw CompetitionServiceError.requestFailed
        }
        let body = http.statusCode == 304 ? previous!.body : data
        let decodeStart = PublishedCompetitionClock.now()
        let results = resource == "results" ? try Self.decodeResults(body, competitionID: id) : []
        let scrambles = resource == "scrambles" ? try Self.decodeScrambles(body, competitionID: id) : []
        let decodeMS = PublishedCompetitionClock.milliseconds(since: decodeStart)
        let date = now()
        try Task.checkCancellation()
        guard cacheGeneration == run else { throw CancellationError() }
        let scope = resource + "|" + id, token = UUID()
        responseTokens[scope] = token; responseOrder.removeAll { $0 == scope }; responseOrder.append(scope)
        while responseOrder.count > 64 { responseTokens[responseOrder.removeFirst()] = nil }
        if resource == "results" {
            resultCache = resultCache.filter { $0.value.1.competitionID != id }
            resultCosts = resultCosts.filter { resultCache[$0.key] != nil }
        } else { scrambleCache[id] = nil; scrambleCosts[id] = nil }
        // Only validated authoritative successes (including empty arrays) replace disk data.
        await cache?.store(.init(body: body, validatedAt: date,
            etag: http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? previous?.etag : nil),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? (http.statusCode == 304 ? previous?.lastModified : nil)), for: key)
        return Response(bytes: data.count, bodyBytes: body.count, results: results, scrambles: scrambles, status: http.statusCode,
            networkMS: networkMS, decodeMS: decodeMS, validatedAt: date, token: token)
    }

    nonisolated static func log(_ metrics: PublishedCompetitionMetrics) {
        #if DEBUG
        print(String(format: "[CompetitionPublished] %@ %@ HTTP=%@ bytes=%d network=%.2fms decode=%.2fms model=%.2fms cache=%@",
            metrics.resource, metrics.competitionID, metrics.httpStatus.map(String.init) ?? "-", metrics.bytes,
            metrics.networkMS, metrics.decodeMS, metrics.modelMS, metrics.cacheHit ? "hit" : "miss"))
        #endif
    }

    static func validCompetitionID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil
    }
    static func decodeResults(_ data: Data, competitionID: String) throws -> [PublishedCompetitionResult] {
        let rows = try JSONDecoder().decode([PublishedCompetitionResult].self, from: data)
        guard rows.allSatisfy({ $0.competitionID == competitionID }), Set(rows.map(\.id)).count == rows.count else {
            throw CompetitionServiceError.requestFailed
        }
        return rows
    }
    static func decodeScrambles(_ data: Data, competitionID: String) throws -> [PublishedCompetitionScramble] {
        let rows = try JSONDecoder().decode([PublishedCompetitionScramble].self, from: data)
        guard rows.allSatisfy({ $0.competitionID == competitionID }), Set(rows.map(\.id)).count == rows.count else {
            throw CompetitionServiceError.requestFailed
        }
        return rows
    }
}

nonisolated enum PublishedCompetitionLifecycle: Equatable {
    case unknown, loading, unpublished, published, failed
    static func state(results: [PublishedCompetitionResult]?, requestFailed: Bool) -> Self {
        if let results { return results.isEmpty ? .unpublished : .published }
        return requestFailed ? .failed : .unknown
    }
    var primaryDestinations: [String] { self == .published ? ["info", "results", "scrambles"] : ["info", "register", "competitors"] }
}

@MainActor
final class PublishedCompetitionStore: ObservableObject {
    @Published private(set) var data: PublishedCompetitionData?
    @Published private(set) var recordEvidenceRefreshID = 0
    @Published private(set) var failed = false
    @Published private(set) var loading = false
    @Published private(set) var lifecycle: PublishedCompetitionLifecycle = .unknown
    @Published private(set) var isStale = false
    let service: PublishedCompetitionService
    let scrambles: PublishedCompetitionScramblesStore
    private var selectionStarted: UInt64?
    private var didRender = false
    private var loadedID: String?
    private var requestedCompetition: String?
    private var generation = 0

    init(service: PublishedCompetitionService = .shared) {
        self.service = service
        self.scrambles = PublishedCompetitionScramblesStore(service: service)
    }

    #if DEBUG
    convenience init(renderingData: PublishedCompetitionData) {
        self.init()
        data = renderingData
        lifecycle = .published
        loadedID = renderingData.competitionID
        requestedCompetition = renderingData.competitionID
    }
    #endif

    func beginResultsPresentation() { selectionStarted = PublishedCompetitionClock.now(); didRender = false }
    func didPresentResults() {
        guard !didRender, let selectionStarted else { return }
        didRender = true
        #if DEBUG
        print(String(format: "[CompetitionPublished] first-meaningful-results selection-to-row=%.2fms", PublishedCompetitionClock.milliseconds(since: selectionStarted)))
        #endif
    }

    func load(competition: CompetitionSummary, language: String, refresh: Bool = false) async {
        generation += 1
        let run = generation
        if requestedCompetition != competition.id {
            data = nil
            isStale = false
            loadedID = nil
            lifecycle = .unknown
            failed = false
            requestedCompetition = competition.id
        }
        let previousState = lifecycle
        let started = PublishedCompetitionClock.now()
        if data == nil { lifecycle = .loading }
        loading = true
        defer { if run == generation { loading = false } }
        do {
            let id = try await CompetitionService.resolvePublishedCompetitionID(for: competition, languageCode: language)
            try Task.checkCancellation()
            guard run == generation else { return }
            #if DEBUG
            print(String(format: "[CompetitionPublished] identity %@ id=%@ resolve=%.2fms", competition.id, id ?? "not-applicable", PublishedCompetitionClock.milliseconds(since: started)))
            #endif
            guard let id else { lifecycle = .unknown; failed = false; return }
            await loadResolved(id: id, events: competition.eventIDs, refresh: refresh, run: run)
        } catch is CancellationError {
            if run == generation { lifecycle = previousState == .loading ? .unknown : previousState }
        } catch {
            if run == generation {
                if Task.isCancelled { lifecycle = previousState == .loading ? .unknown : previousState }
                else { failed = true; isStale = data != nil; if data == nil { lifecycle = .failed } }
            }
        }
    }

    func load(id: String?, events: [String], refresh: Bool = false) async {
        generation += 1
        let run = generation
        guard let id, PublishedCompetitionService.validCompetitionID(id) else {
            loading = false
            if data == nil { lifecycle = .unknown }
            return
        }
        await loadResolved(id: id, events: events, refresh: refresh, run: run)
    }

    private func loadResolved(id: String, events: [String], refresh: Bool, run: Int) async {
        if let loadedID, loadedID != id {
            data = nil
            isStale = false
            self.loadedID = nil
            lifecycle = .unknown
            failed = false
        }
        let previousState = lifecycle
        loading = true
        if data == nil { lifecycle = .loading }
        do {
            if let cached = await service.cachedResults(competitionID: id, eventOrder: events) {
                try Task.checkCancellation()
                guard run == generation else { return }
                let state = PublishedCompetitionLifecycle.state(results: cached.data.results, requestFailed: false)
                data = state == .published ? cached.data : nil
                isStale = cached.isStale
                lifecycle = state; loadedID = id
                if state == .published { await scrambles.hydrateCached(id: id) }
                try Task.checkCancellation()
                guard run == generation else { return }
            }
            let loaded = try await service.resultSnapshot(competitionID: id, eventOrder: events, refresh: refresh)
            let snapshot = loaded.data
            try Task.checkCancellation()
            guard run == generation else { return }
            let state = PublishedCompetitionLifecycle.state(results: snapshot.results, requestFailed: false)
            let updateStarted = PublishedCompetitionClock.now()
            data = state == .published ? snapshot : nil
            if refresh { recordEvidenceRefreshID += 1 }
            isStale = loaded.isStale
            lifecycle = state
            failed = false
            loadedID = id
            PublishedCompetitionService.log(loaded.metrics)
            #if DEBUG
            print(String(format: "[CompetitionPublished] published-state %@ update=%.2fms", id, PublishedCompetitionClock.milliseconds(since: updateStarted)))
            #endif
        } catch is CancellationError {
            if run == generation { lifecycle = previousState == .loading ? .unknown : previousState }
        } catch {
            if run == generation {
                if Task.isCancelled { lifecycle = previousState == .loading ? .unknown : previousState }
                else { failed = true; isStale = data != nil; if data == nil { lifecycle = .failed } }
            }
        }
        if run == generation { loading = false }
    }
}

@MainActor
final class PublishedCompetitionScramblesStore: ObservableObject {
    @Published private(set) var sets: [PublishedScrambleSet] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var isStale = false
    private let service: PublishedCompetitionService
    private var competitionID: String?
    private var generation = 0
    private var loaded = false
    private var consumers: Set<UUID> = []

    init(service: PublishedCompetitionService = .shared) { self.service = service }

    /// Reading an already-published disk snapshot is not a new scramble request.
    func hydrateCached(id: String) async {
        if competitionID != id {
            generation += 1; consumers.removeAll()
            competitionID = id; sets = []; failed = false; loaded = false; isStale = false
        }
        let run = generation
        guard let cached = await service.cachedScrambleSnapshot(competitionID: id), !Task.isCancelled,
              generation == run, competitionID == id else { return }
        sets = cached.sets; loaded = true; isStale = cached.isStale
    }

    func load(id: String, refresh: Bool = false) async {
        if competitionID != id || refresh {
            generation += 1
            consumers.removeAll()
        }
        let run = generation
        if competitionID != id { sets = []; failed = false; loaded = false; isStale = false }
        let consumer = UUID()
        consumers.insert(consumer)
        competitionID = id; loading = true
        defer {
            if generation == run {
                consumers.remove(consumer)
                loading = !consumers.isEmpty
            }
        }
        do {
            await hydrateCached(id: id)
            try Task.checkCancellation()
            guard generation == run else { return }
            let fetched = try await service.scrambles(competitionID: id, refresh: refresh)
            try Task.checkCancellation()
            guard generation == run else { return }
            sets = fetched; failed = false; loaded = true
            isStale = false
        } catch is CancellationError { } catch { if generation == run, !Task.isCancelled { failed = true; isStale = loaded } }
    }
}
