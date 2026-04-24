import Foundation

struct CompetitionSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let startDate: Date
    let endDate: Date
    let registrationOpen: Date?
    let registrationClose: Date?
    let competitorLimit: Int?
    let venue: String
    let venueAddress: String
    let venueDetails: String?
    let city: String
    let countryISO2: String
    let latitude: Double?
    let longitude: Double?
    let url: String
    let website: String?
    let dateRange: String
    let eventIDs: [String]
    let localizedRegionLineOverride: String?
    let localizedAddressLineOverride: String?
    let localizedStatusOverride: CompetitionAvailabilityStatus?
    let localizedRegistrationStartOverride: Date?
    let localizedWaitlistStartOverride: Date?

    var locationLine: String {
        if let localizedRegionLineOverride, !localizedRegionLineOverride.isEmpty {
            return localizedRegionLineOverride
        }
        return [city, localizedCountryName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var venueLine: String {
        if let localizedAddressLineOverride, !localizedAddressLineOverride.isEmpty {
            return localizedAddressLineOverride
        }
        return [venue, venueDetails].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    var localizedCountryName: String {
        Locale.current.localizedString(forRegionCode: countryISO2) ?? countryISO2
    }
}

struct CompetitionRecognizedCountry: Identifiable, Hashable, Sendable, Codable {
    let code: String
    let wcaName: String

    var id: String { code }

    func localizedTitle(languageCode: String) -> String {
        let localized = localizedCountryName(for: code, languageCode: languageCode)
        return localized == code ? wcaName : localized
    }
}

enum CompetitionContinent: String, CaseIterable, Identifiable, Hashable, Sendable {
    case asia
    case northAmerica
    case southAmerica
    case oceania
    case europe
    case africa

    var id: String { rawValue }

    fileprivate var matches: (continent: String, subcontinent: String?) {
        switch self {
        case .asia:
            return ("142", nil)
        case .northAmerica:
            return ("019", "northAmerica")
        case .southAmerica:
            return ("019", "005")
        case .oceania:
            return ("009", nil)
        case .europe:
            return ("150", nil)
        case .africa:
            return ("002", nil)
        }
    }

    fileprivate var countryCodes: Set<String> {
        switch self {
        case .asia:
            return asiaCountryCodes
        case .northAmerica:
            return northAmericaCountryCodes
        case .southAmerica:
            return southAmericaCountryCodes
        case .oceania:
            return oceaniaCountryCodes
        case .europe:
            return europeCountryCodes
        case .africa:
            return africaCountryCodes
        }
    }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .asia:
            return localizedCompetitionString(key: "competitions.continent.asia", languageCode: languageCode)
        case .northAmerica:
            return localizedCompetitionString(key: "competitions.continent.north_america", languageCode: languageCode)
        case .southAmerica:
            return localizedCompetitionString(key: "competitions.continent.south_america", languageCode: languageCode)
        case .oceania:
            return localizedCompetitionString(key: "competitions.continent.oceania", languageCode: languageCode)
        case .europe:
            return localizedCompetitionString(key: "competitions.continent.europe", languageCode: languageCode)
        case .africa:
            return localizedCompetitionString(key: "competitions.continent.africa", languageCode: languageCode)
        }
    }
}

enum CompetitionRegionFilter: Hashable, Identifiable, Sendable {
    case all
    case continent(CompetitionContinent)
    case country(String)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .continent(let continent):
            return "continent-\(continent.rawValue)"
        case .country(let code):
            return "country-\(code)"
        }
    }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .all:
            return localizedCompetitionString(key: "competitions.region.all", languageCode: languageCode)
        case .continent(let continent):
            return continent.localizedTitle(languageCode: languageCode)
        case .country(let code):
            return localizedCountryName(for: code, languageCode: languageCode)
        }
    }

    init?(storedID: String) {
        if storedID == "all" {
            self = .all
            return
        }

        if let continentRawValue = storedID.split(separator: "-", maxSplits: 1).last,
           storedID.hasPrefix("continent-"),
           let continent = CompetitionContinent(rawValue: String(continentRawValue)) {
            self = .continent(continent)
            return
        }

        if let countryCode = storedID.split(separator: "-", maxSplits: 1).last,
           storedID.hasPrefix("country-"),
           !countryCode.isEmpty {
            self = .country(String(countryCode))
            return
        }

        return nil
    }

}

enum CompetitionAvailabilityStatus: String, CaseIterable, Identifiable, Codable {
    case upcoming
    case registrationNotOpenYet
    case registrationOpen
    case waitlist
    case ongoing
    case ended

    var id: String { rawValue }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .upcoming:
            return localizedCompetitionString(key: "competitions.status.upcoming", languageCode: languageCode)
        case .registrationNotOpenYet:
            return localizedCompetitionString(key: "competitions.status.registration_not_open_yet", languageCode: languageCode)
        case .registrationOpen:
            return localizedCompetitionString(key: "competitions.status.registration_open", languageCode: languageCode)
        case .waitlist:
            return localizedCompetitionString(key: "competitions.status.waitlist", languageCode: languageCode)
        case .ongoing:
            return localizedCompetitionString(key: "competitions.status.ongoing", languageCode: languageCode)
        case .ended:
            return localizedCompetitionString(key: "competitions.status.ended", languageCode: languageCode)
        }
    }
}

enum CompetitionEventFilter: String, CaseIterable, Identifiable {
    case all
    case twoByTwo
    case threeByThree
    case fourByFour
    case fiveByFive
    case sixBySix
    case sevenBySeven
    case threeBlind
    case fewestMoves
    case oneHanded
    case clock
    case megaminx
    case pyraminx
    case skewb
    case squareOne
    case fourBlind
    case fiveBlind
    case multiBlind

    var id: String { rawValue }

    static var selectableCases: [CompetitionEventFilter] {
        allCases.filter { $0 != .all }
    }

    var wcaEventID: String {
        switch self {
        case .all: return ""
        case .twoByTwo: return "222"
        case .threeByThree: return "333"
        case .fourByFour: return "444"
        case .fiveByFive: return "555"
        case .sixBySix: return "666"
        case .sevenBySeven: return "777"
        case .threeBlind: return "333bf"
        case .fewestMoves: return "333fm"
        case .oneHanded: return "333oh"
        case .clock: return "clock"
        case .megaminx: return "minx"
        case .pyraminx: return "pyram"
        case .skewb: return "skewb"
        case .squareOne: return "sq1"
        case .fourBlind: return "444bf"
        case .fiveBlind: return "555bf"
        case .multiBlind: return "333mbf"
        }
    }

    func localizedTitle(languageCode: String) -> String {
        let key: String
        switch self {
        case .all:
            key = "competitions.event.all"
        case .twoByTwo:
            key = "event.2x2"
        case .threeByThree:
            key = "event.3x3"
        case .fourByFour:
            key = "event.4x4"
        case .fiveByFive:
            key = "event.5x5"
        case .sixBySix:
            key = "event.6x6"
        case .sevenBySeven:
            key = "event.7x7"
        case .threeBlind:
            key = "event.3x3bld"
        case .fewestMoves:
            key = "event.3x3fm"
        case .oneHanded:
            key = "event.3x3oh"
        case .clock:
            key = "event.clock"
        case .megaminx:
            key = "event.megaminx"
        case .pyraminx:
            key = "event.pyraminx"
        case .skewb:
            key = "event.skewb"
        case .squareOne:
            key = "event.square1"
        case .fourBlind:
            key = "event.4x4bld"
        case .fiveBlind:
            key = "event.5x5bld"
        case .multiBlind:
            key = "event.3x3mbld"
        }
        return localizedCompetitionString(key: key, languageCode: languageCode)
    }
}

enum CompetitionYearFilter: String, CaseIterable, Identifiable {
    case all
    case current
    case next

    var id: String { rawValue }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .all:
            return localizedCompetitionString(key: "competitions.year.all", languageCode: languageCode)
        case .current:
            return localizedCompetitionString(key: "competitions.year.current", languageCode: languageCode)
        case .next:
            return localizedCompetitionString(key: "competitions.year.next", languageCode: languageCode)
        }
    }
}

enum CompetitionStatusFilter: String, CaseIterable, Identifiable {
    case upcoming
    case registrationNotOpenYet
    case registrationOpen
    case waitlist
    case ongoing
    case ended

    var id: String { rawValue }

    static var selectableCases: [CompetitionStatusFilter] {
        [.ongoing, .registrationOpen, .upcoming, .registrationNotOpenYet, .ended]
    }

    var availabilityStatus: CompetitionAvailabilityStatus {
        switch self {
        case .upcoming:
            return .upcoming
        case .registrationNotOpenYet:
            return .registrationNotOpenYet
        case .registrationOpen:
            return .registrationOpen
        case .waitlist:
            return .waitlist
        case .ongoing:
            return .ongoing
        case .ended:
            return .ended
        }
    }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .ongoing:
            return localizedCompetitionString(key: "competitions.status.ongoing", languageCode: languageCode)
        case .registrationOpen:
            return localizedCompetitionString(key: "competitions.filter.status.registration_open_group", languageCode: languageCode)
        case .upcoming:
            return localizedCompetitionString(key: "competitions.filter.status.recent", languageCode: languageCode)
        case .registrationNotOpenYet:
            return localizedCompetitionString(key: "competitions.filter.status.future_registration", languageCode: languageCode)
        case .waitlist:
            return localizedCompetitionString(key: "competitions.filter.status.future_registration", languageCode: languageCode)
        case .ended:
            return localizedCompetitionString(key: "competitions.status.ended", languageCode: languageCode)
        }
    }
}

struct CompetitionQuery: Sendable, Hashable {
    let languageCode: String
    let region: CompetitionRegionFilter
    let events: Set<CompetitionEventFilter>
    let year: CompetitionYearFilter
    let status: CompetitionStatusFilter
}

struct CompetitionPageResult: Sendable {
    let competitions: [CompetitionSummary]
    let nextPage: Int?
    let totalCount: Int?
}

struct CompetitionDetailTextBlock: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let body: String
}

struct CompetitionScheduleEntry: Identifiable, Hashable, Sendable {
    let id: String
    let timeText: String
    let title: String
    let detailText: String?
}

struct CompetitionScheduleDay: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let entries: [CompetitionScheduleEntry]
}

struct CompetitionCompetitorPreview: Identifiable, Hashable, Sendable {
    let id: String
    let number: String?
    let name: String
    let gender: String?
    let subtitle: String?
    let registeredEventIDs: [String]
}

struct CompetitionPsychItem: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let rank: Int
    let resultText: String
}

struct CompetitionCompetitorPsychPreview: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let items: [CompetitionPsychItem]
}

enum CompetitionTopCuberTier: String, Hashable, Sendable, Codable {
    case wr
    case cr
    case nr
}

struct CompetitionTopCuberBadge: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let eventID: String
    let tier: CompetitionTopCuberTier
}

struct CompetitionTopCuberPreview: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let badges: [CompetitionTopCuberBadge]
}

struct CompetitionLiveFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

struct CompetitionLiveRoundOption: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let roundID: String
    let eventName: String
    let roundName: String
    let statusText: String?
    let recordedCount: Int
    let totalCount: Int
    let formatID: String
}

struct CompetitionLiveStaticMessage: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let timestamp: Int
    let text: String
    let linkURL: URL?
}

struct CompetitionLiveSumOfRanksItem: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let rankText: String
}

struct CompetitionLiveSumOfRanksEntry: Identifiable, Hashable, Sendable {
    let id: String
    let placeText: String
    let name: String
    let region: String
    let totalText: String
    let items: [CompetitionLiveSumOfRanksItem]
}

struct CompetitionLiveSumOfRanksContent: Hashable, Sendable {
    let eventIDs: [String]
    let entries: [CompetitionLiveSumOfRanksEntry]
}

struct CompetitionLivePodiumPlacement: Identifiable, Hashable, Sendable {
    let id: String
    let placeText: String
    let name: String
    let bestText: String
    let averageText: String
    let region: String
}

struct CompetitionLivePodiumSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let placements: [CompetitionLivePodiumPlacement]
}

struct CompetitionLiveContent: Hashable, Sendable {
    let competitionID: Int
    let sourceType: String
    let roundOptions: [CompetitionLiveRoundOption]
    let filterOptions: [CompetitionLiveFilterOption]
    let defaultEventID: String
    let defaultRoundID: String
    let defaultFilterValue: String
    let staticMessages: [CompetitionLiveStaticMessage]
    let sumOfRanksURL: URL?
    let podiumsURL: URL?
    let sumOfRanksContent: CompetitionLiveSumOfRanksContent?
    let podiumSections: [CompetitionLivePodiumSection]
}

struct CompetitionWCALiveRound: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let eventName: String
    let roundName: String
    let number: Int?
    let isActive: Bool
    let isOpen: Bool
    let results: [CompetitionWCALiveResultPreview]
}

struct CompetitionWCALiveResultPreview: Identifiable, Hashable, Sendable {
    let id: String
    let ranking: Int
    let name: String
    let region: String?
    let attempts: [Int]
    let best: Int
    let average: Int
}

struct CompetitionWCALiveRoom: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let currentActivityName: String?
    let currentActivityStart: Date?
    let currentActivityEnd: Date?
    let nextActivityName: String?
    let nextActivityStart: Date?
}

struct CompetitionWCALiveVenue: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let countryName: String?
    let rooms: [CompetitionWCALiveRoom]
}

struct CompetitionWCALiveContent: Hashable, Sendable {
    let competitionID: Int
    let eventIDs: [String]
    let rounds: [CompetitionWCALiveRound]
    let venues: [CompetitionWCALiveVenue]
}

enum CompetitionLiveAvailability: String, Hashable, Sendable {
    case available
    case unavailable
    case upcoming
    case ended
}

struct CompetitionDetailContent: Hashable, Sendable {
    let overviewBlocks: [CompetitionDetailTextBlock]
    let noteBlocks: [CompetitionDetailTextBlock]
    let travelBlocks: [CompetitionDetailTextBlock]
    let registerBlocks: [CompetitionDetailTextBlock]
    let scheduleDays: [CompetitionScheduleDay]
    let competitorsCount: Int?
    let competitorPreviews: [CompetitionCompetitorPreview]
    let registrationRequiresSignIn: Bool
    let liveAvailability: CompetitionLiveAvailability
    let liveURLOverride: URL?
    let liveContent: CompetitionLiveContent?
    let wcaLiveContent: CompetitionWCALiveContent?

    static let empty = CompetitionDetailContent(
        overviewBlocks: [],
        noteBlocks: [],
        travelBlocks: [],
        registerBlocks: [],
        scheduleDays: [],
        competitorsCount: nil,
        competitorPreviews: [],
        registrationRequiresSignIn: false,
        liveAvailability: .upcoming,
        liveURLOverride: nil,
        liveContent: nil,
        wcaLiveContent: nil
    )
}

nonisolated private func competitionSelectableEventIDs() -> [String] {
    [
        "222", "333", "444", "555", "666", "777",
        "333bf", "333fm", "333oh", "clock", "minx", "pyram",
        "skewb", "sq1", "444bf", "555bf", "333mbf"
    ]
}

struct CompetitionCacheSnapshot: Sendable {
    let competitions: [CompetitionSummary]
    let totalCount: Int?
    let lastUpdated: Date
}

enum CompetitionServiceError: LocalizedError {
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return currentAppLocalizedString("competitions.error_invalid_url")
        case .requestFailed:
            return currentAppLocalizedString("competitions.error_request_failed")
        }
    }
}

enum CompetitionService {
    static func warmRecognizedCountriesCache() async {
        _ = try? await CompetitionRecognizedCountryStore.shared.recognizedCountries()
    }

    static func warmCompetitionLocalizedNamesCache(languageCode: String) async {
        guard cubingLanguageCode(for: languageCode) == "zh_cn" else { return }
        _ = await CompetitionLocalizedNameStore.shared.localizedCompetitionNames {
            await fetchCompetitionNameMapFromCubing(languageCode: languageCode)
        }
    }

    static func fetchCompetitionDetail(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionDetailContent {
        if competition.countryISO2.uppercased() == "CN" {
            return await fetchCubingCompetitionDetail(for: competition, languageCode: languageCode) ?? .empty
        }

        return await fetchWCACompetitionDetail(for: competition, languageCode: languageCode) ?? .empty
    }

    static func fetchCompetitionPsychPreviews(
        for competition: CompetitionSummary,
        languageCode: String,
        eventID: String?
    ) async -> [CompetitionCompetitorPsychPreview] {
        let trimmedEventID = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetEventID = trimmedEventID.isEmpty ? nil : trimmedEventID

        if competition.countryISO2.uppercased() == "CN" {
            return await fetchCubingPsychPreviews(
                for: competition,
                languageCode: languageCode,
                eventID: targetEventID
            )
        }

        return await fetchWCAPsychPreviews(
            for: competition,
            languageCode: languageCode,
            eventID: targetEventID
        )
    }

    static func fetchCompetitionTopCuberPreviews(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> [CompetitionTopCuberPreview]? {
        if let cached = await CompetitionTopCuberStore.shared.previews(for: cacheKeyForTopCubers(competitionID: competition.id)) {
            return cached
        }

        guard let fetched = await fetchWCATopCuberPreviews(for: competition, languageCode: languageCode) else {
            return nil
        }
        await CompetitionTopCuberStore.shared.store(
            fetched,
            for: cacheKeyForTopCubers(competitionID: competition.id)
        )
        return fetched
    }

    static func cachedCompetitionTopCuberPreviews(
        for competitionID: String
    ) async -> [CompetitionTopCuberPreview]? {
        await CompetitionTopCuberStore.shared.previews(for: cacheKeyForTopCubers(competitionID: competitionID))
    }

    static func fetchCompetitionWCALiveContent(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionWCALiveContent? {
        guard competition.countryISO2.uppercased() != "CN" else { return nil }
        return await fetchWCALiveContent(for: competition, languageCode: languageCode, liveURL: nil)
    }

    private static func fetchWCATopCuberPreviews(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> [CompetitionTopCuberPreview]? {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(competition.id)/wcif/public") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let wcif = try? decoder.decode(WCAPublicWCIF.self, from: data) else {
            return nil
        }

        let acceptedPeople = wcif.persons.filter { person in
            guard let registration = person.registration else { return false }
            if let isCompeting = registration.isCompeting {
                return isCompeting
            }
            return registration.status?.lowercased() == "accepted"
        }

        var badgesByPersonID: [String: [CompetitionTopCuberBadge]] = [:]
        var namesByPersonID: [String: String] = [:]

        for person in acceptedPeople {
            guard let wcaId = person.wcaId, !wcaId.isEmpty else { continue }
            let relevantPersonalBests = (person.personalBests ?? []).filter { personalBest in
                competition.eventIDs.contains(personalBest.eventId)
            }

            let badges = relevantPersonalBests.compactMap { personalBest -> CompetitionTopCuberBadge? in
                guard let tier = topCuberTier(for: personalBest) else { return nil }
                return CompetitionTopCuberBadge(
                    id: "\(wcaId)-\(personalBest.eventId)-\(tier.rawValue)",
                    eventID: personalBest.eventId,
                    tier: tier
                )
            }

            guard !badges.isEmpty else { continue }

            namesByPersonID[wcaId] = person.name
            badgesByPersonID[wcaId] = mergeTopCuberBadges(
                existing: badgesByPersonID[wcaId] ?? [],
                incoming: badges
            )
        }

        let eventOrder = competitionSelectableEventIDs()

        let unsortedPreviews: [CompetitionTopCuberPreview] = badgesByPersonID.compactMap { (personID: String, badges: [CompetitionTopCuberBadge]) in
            guard let name = namesByPersonID[personID], !badges.isEmpty else { return nil }
            let sortedBadges = badges.sorted { lhs, rhs in
                if lhs.tier != rhs.tier {
                    return topCuberTierPriority(lhs.tier) < topCuberTierPriority(rhs.tier)
                }
                return (eventOrder.firstIndex(of: lhs.eventID) ?? .max) < (eventOrder.firstIndex(of: rhs.eventID) ?? .max)
            }
            return CompetitionTopCuberPreview(id: personID, name: name, badges: sortedBadges)
        }
        let previews = unsortedPreviews.sorted { lhs, rhs in
            let lhsPriority = lhs.badges.map(\.tier).map { topCuberTierPriority($0) }.min() ?? .max
            let rhsPriority = rhs.badges.map(\.tier).map { topCuberTierPriority($0) }.min() ?? .max
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return previews
    }

    static func cachedCompetitions(for query: CompetitionQuery) async -> CompetitionCacheSnapshot? {
        guard let snapshot = await CompetitionQueryCacheStore.shared.snapshot(for: cacheKey(for: query)) else {
            return nil
        }

        return CompetitionCacheSnapshot(
            competitions: snapshot.competitions.map(strippingLocalizedOverrides),
            totalCount: snapshot.totalCount,
            lastUpdated: snapshot.lastUpdated
        )
    }

    static func filterCompetitions(
        _ competitions: [CompetitionSummary],
        for query: CompetitionQuery,
        now: Date = Date()
    ) -> [CompetitionSummary] {
        competitions
            .filter { matchesStatus($0, status: query.status, now: now) }
            .sorted { lhs, rhs in
                let lhsStatus = availabilityStatus(for: lhs, now: now)
                let rhsStatus = availabilityStatus(for: rhs, now: now)

                if lhsStatus == .ended && rhsStatus == .ended {
                    if lhs.endDate != rhs.endDate {
                        return lhs.endDate > rhs.endDate
                    }
                } else if lhsStatus == .ended {
                    return false
                } else if rhsStatus == .ended {
                    return true
                } else if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }

                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return lhs.id < rhs.id
            }
    }

    static func cacheCompetitions(
        _ competitions: [CompetitionSummary],
        totalCount: Int?,
        for query: CompetitionQuery
    ) async {
        let normalizedCompetitions = filterCompetitions(competitions, for: query)
        let snapshot = CompetitionCacheSnapshot(
            competitions: normalizedCompetitions.map(strippingLocalizedOverrides),
            totalCount: totalCount,
            lastUpdated: Date()
        )
        await CompetitionQueryCacheStore.shared.store(snapshot, for: cacheKey(for: query))
    }

    static func fetchCompetitionsPage(query: CompetitionQuery, page: Int) async throws -> CompetitionPageResult {
        let today = Calendar.current.startOfDay(for: Date())
        var queryItems: [URLQueryItem] = []

        switch query.status {
        case .upcoming:
            queryItems.append(URLQueryItem(name: "start", value: apiDateString(from: today.addingTimeInterval(-86400 * 14))))
            queryItems.append(URLQueryItem(name: "sort", value: "start_date"))
        case .registrationNotOpenYet, .registrationOpen, .waitlist:
            queryItems.append(URLQueryItem(name: "start", value: apiDateString(from: today)))
            queryItems.append(URLQueryItem(name: "sort", value: "start_date"))
        case .ongoing:
            queryItems.append(URLQueryItem(name: "start", value: apiDateString(from: today.addingTimeInterval(-86400 * 14))))
            queryItems.append(URLQueryItem(name: "end", value: apiDateString(from: today)))
            queryItems.append(URLQueryItem(name: "sort", value: "start_date"))
        case .ended:
            queryItems.append(URLQueryItem(name: "end", value: apiDateString(from: today.addingTimeInterval(-86400))))
        }

        switch query.year {
        case .all:
            break
        case .current:
            if let range = yearRange(forOffset: 0) {
                queryItems = replacingDateBounds(existing: queryItems, with: range)
            }
        case .next:
            if let range = yearRange(forOffset: 1) {
                queryItems = replacingDateBounds(existing: queryItems, with: range)
            }
        }

        switch query.region {
        case .all, .continent:
            break
        case .country(let code):
            queryItems.append(URLQueryItem(name: "country_iso2", value: code))
        }

        let payloadPage = try await fetchCompetitionPayloadPage(
            queryItems: queryItems,
            page: page,
            languageCode: query.languageCode
        )

        let baseCompetitions = payloadPage.payloads
            .map(\.summary)
            .filter { matchesRegion($0, region: query.region) }
            .filter { matchesEvents($0, selectedEvents: query.events) }
        let localizedCompetitions = await localizeCompetitionNamesIfNeeded(
            baseCompetitions,
            languageCode: query.languageCode
        )
        let competitions = localizedCompetitions
            .filter { matchesStatus($0, status: query.status, now: Date()) }
            .sorted { lhs, rhs in
                let lhsStatus = availabilityStatus(for: lhs, now: Date())
                let rhsStatus = availabilityStatus(for: rhs, now: Date())

                if lhsStatus == .ended || rhsStatus == .ended {
                    return lhs.endDate > rhs.endDate
                }

                return lhs.startDate < rhs.startDate
            }

        return CompetitionPageResult(
            competitions: competitions,
            nextPage: payloadPage.payloads.count < 25 ? nil : page + 1,
            totalCount: payloadPage.totalCount
        )
    }

    static func fetchRecognizedCountries() async throws -> [CompetitionRecognizedCountry] {
        try await CompetitionRecognizedCountryStore.shared.recognizedCountries()
    }

    static func localizeCompetitionNamesIfNeeded(
        _ competitions: [CompetitionSummary],
        languageCode: String
    ) async -> [CompetitionSummary] {
        guard cubingLanguageCode(for: languageCode) == "zh_cn", !competitions.isEmpty else {
            return competitions
        }

        let localizedNames = await CompetitionLocalizedNameStore.shared.localizedCompetitionNames {
            await fetchCompetitionNameMapFromCubing(languageCode: languageCode)
        }

        return competitions.map { competition in
            let localizedInfo = localizedNames[normalizeCompetitionLookupKey(competition.id)]
                ?? localizedNames[normalizeCompetitionLookupKey(competition.website ?? "")]
                ?? localizedNames[normalizeCompetitionLookupKey(competition.name)]

            let usesCubingChinaOverrides = competition.countryISO2 == "CN"
            let localizedName = usesCubingChinaOverrides ? (localizedInfo?.name ?? competition.name) : competition.name
            let localizedRegionLineOverride: String?
            let localizedAddressLineOverride: String?
            let localizedStatusOverrideValue: CompetitionAvailabilityStatus?
            let localizedCountryName = localizedCountryName(for: competition.countryISO2, languageCode: languageCode)
            if usesCubingChinaOverrides,
               let regionPrimary = localizedInfo?.regionPrimary, !regionPrimary.isEmpty,
               let regionSecondary = localizedInfo?.regionSecondary, !regionSecondary.isEmpty {
                localizedRegionLineOverride = "\(regionPrimary), \(regionSecondary) · \(localizedCountryName)"
            } else {
                localizedRegionLineOverride = nil
            }
            if usesCubingChinaOverrides,
               let address = localizedInfo?.address,
               !address.isEmpty {
                localizedAddressLineOverride = localizedVenueLine(from: address)
            } else {
                localizedAddressLineOverride = nil
            }
            if usesCubingChinaOverrides {
                localizedStatusOverrideValue = localizedStatusOverride(for: competition, localizedInfo: localizedInfo, now: Date())
            } else {
                localizedStatusOverrideValue = nil
            }

            guard localizedName != competition.name
                || localizedRegionLineOverride != nil
                || localizedAddressLineOverride != nil
                || localizedStatusOverrideValue != nil else { return competition }
            return CompetitionSummary(
                id: competition.id,
                name: localizedName,
                startDate: competition.startDate,
                endDate: competition.endDate,
                registrationOpen: competition.registrationOpen,
                registrationClose: competition.registrationClose,
                competitorLimit: competition.competitorLimit,
                venue: competition.venue,
                venueAddress: competition.venueAddress,
                venueDetails: competition.venueDetails,
                city: competition.city,
                countryISO2: competition.countryISO2,
                latitude: competition.latitude,
                longitude: competition.longitude,
                url: competition.url,
                website: competition.website,
                dateRange: competition.dateRange,
                eventIDs: competition.eventIDs,
                localizedRegionLineOverride: localizedRegionLineOverride,
                localizedAddressLineOverride: localizedAddressLineOverride,
                localizedStatusOverride: localizedStatusOverrideValue,
                localizedRegistrationStartOverride: usesCubingChinaOverrides ? localizedInfo?.registrationStart : nil,
                localizedWaitlistStartOverride: usesCubingChinaOverrides ? localizedInfo?.reopenRegistration : nil
            )
        }
    }

    private static func localizedStatusOverride(
        for competition: CompetitionSummary,
        localizedInfo: LocalizedCompetitionInfo?,
        now: Date
    ) -> CompetitionAvailabilityStatus? {
        guard let localizedInfo else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = calendar.startOfDay(for: competition.startDate)
        let endOfCompetition = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let registrationStart = localizedInfo.registrationStart, now < registrationStart {
            return .registrationNotOpenYet
        }

        if let pauseRegistrationStart = localizedInfo.pauseRegistrationStart,
           let reopenRegistration = localizedInfo.reopenRegistration,
           now >= pauseRegistrationStart && now < reopenRegistration {
            return .waitlist
        }

        if let reopenRegistration = localizedInfo.reopenRegistration,
           let registrationClose = localizedInfo.registrationClose,
           now >= reopenRegistration && now <= registrationClose {
            return .waitlist
        }

        if let registrationStart = localizedInfo.registrationStart,
           let registrationClose = localizedInfo.registrationClose,
           now >= registrationStart && now <= registrationClose {
            return .registrationOpen
        }

        return nil
    }

    private static func isFutureWaitlist(for competition: CompetitionSummary, now: Date) -> Bool {
        guard let waitlistStart = competition.localizedWaitlistStartOverride else {
            return false
        }
        return now < waitlistStart
    }

    private static func localizedVenueLine(from address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return address }

        if let segments = splitLocalizedVenueSegments(from: trimmed), !segments.isEmpty {
            return segments.joined(separator: " · ")
        }

        return trimmed
    }

    private static func splitLocalizedVenueSegments(from address: String) -> [String]? {
        if let bracketRange = address.range(of: "（"),
           let closingRange = address.range(of: "）", range: bracketRange.upperBound..<address.endIndex) {
            let venue = String(address[..<bracketRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let details = String(address[bracketRange.upperBound..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !venue.isEmpty, containsVenueDetailKeyword(details) {
                return splitPrimaryVenueSegment(from: venue) + [details]
            }
        }

        let patterns = [
            #"((?:地下一?|负)?[一二三四五六七八九十百0-9]+\s*[层楼].*)$"#,
            #"((?:[一二三四五六七八九十百0-9]+(?:、[一二三四五六七八九十百0-9]+)?号电梯.*))$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsAddress = address as NSString
            let range = NSRange(location: 0, length: nsAddress.length)
            guard let match = regex.firstMatch(in: address, options: [], range: range),
                  match.numberOfRanges > 1 else {
                continue
            }

            let detailsRange = match.range(at: 1)
            guard detailsRange.location != NSNotFound else { continue }

            let details = nsAddress.substring(with: detailsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let venue = nsAddress.substring(to: detailsRange.location).trimmingCharacters(in: .whitespacesAndNewlines)

            if !venue.isEmpty, !details.isEmpty {
                return splitPrimaryVenueSegment(from: venue) + [details]
            }
        }

        let venueSegments = splitPrimaryVenueSegment(from: address)
        return venueSegments.count > 1 ? venueSegments : nil
    }

    private static func containsVenueDetailKeyword(_ value: String) -> Bool {
        let detailKeywords = [
            "楼", "层", "厅", "室", "会堂", "报告厅",
            "会议厅", "宴会厅", "培训室", "课室", "号馆"
        ]
        return detailKeywords.contains { value.contains($0) }
    }

    private static func splitPrimaryVenueSegment(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let addressSplit = splitAddressPrefix(from: trimmed) {
            return [addressSplit.prefix] + splitVenueBody(from: addressSplit.remainder)
        }

        return splitVenueBody(from: trimmed)
    }

    private static func splitAddressPrefix(from value: String) -> (prefix: String, remainder: String)? {
        let addressPrefixKeywords = ["号", "路", "街", "大道", "巷", "道", "镇", "区", "县", "市", "村", "号院", "弄", "里"]
        let patterns = [
            #"^(.+?号)\s+(.+)$"#,
            #"^(.+?号)(.+)$"#,
            #"^(.+?座)\s+(.+)$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsValue = value as NSString
                let range = NSRange(location: 0, length: nsValue.length)
                if let match = regex.firstMatch(in: value, options: [], range: range),
                   match.numberOfRanges == 3 {
                    let prefix = nsValue.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let remainder = nsValue.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !prefix.isEmpty,
                       !remainder.isEmpty,
                       addressPrefixKeywords.contains(where: { prefix.contains($0) }),
                       containsVenueBodyKeyword(remainder) {
                        return (prefix, remainder)
                    }
                }
            }
        }

        return nil
    }

    private static func splitVenueBody(from value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let venueBoundaryPatterns = [
            #"^(.+?(?:大学))(.*(?:学院.*活动中心|活动中心|会堂|体育馆|球馆|展厅).*)$"#,
            #"^(.+?(?:中学|书院))(.*(?:活动中心|会堂|体育馆|球馆|展厅).*)$"#,
            #"^(.+?(?:酒店|大酒店|会展中心|会议中心|展览中心|国际展览中心|大厦|大楼|公寓|广场|总部|校区))(.*(?:活动中心|会堂|体育馆|球馆|展厅|多功能厅|会议厅|宴会厅|报告厅|培训室|课室).*)$"#
        ]

        for pattern in venueBoundaryPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsValue = trimmed as NSString
                let range = NSRange(location: 0, length: nsValue.length)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   match.numberOfRanges == 3 {
                    let first = nsValue.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let second = nsValue.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !first.isEmpty, !second.isEmpty {
                        return [first, second]
                    }
                }
            }
        }

        return [trimmed]
    }

    private static func containsVenueBodyKeyword(_ value: String) -> Bool {
        let keywords = [
            "大学", "学院", "中学", "书院", "酒店", "大酒店", "会展中心", "会议中心",
            "展览中心", "国际展览中心", "大厦", "大楼", "公寓", "广场", "总部", "校区",
            "活动中心", "会堂", "体育馆", "球馆", "展厅", "多功能厅", "会议厅", "宴会厅", "报告厅", "培训室", "课室"
        ]
        return keywords.contains { value.contains($0) }
    }

    private static func matchesRegion(_ competition: CompetitionSummary, region: CompetitionRegionFilter) -> Bool {
        switch region {
        case .all:
            return true
        case .country(let code):
            return competition.countryISO2 == code
        case .continent(let continent):
            return continent.countryCodes.contains(competition.countryISO2)
        }
    }

    private static func matchesEvents(_ competition: CompetitionSummary, selectedEvents: Set<CompetitionEventFilter>) -> Bool {
        let allSelectableEvents = Set(CompetitionEventFilter.selectableCases)
        if selectedEvents.isEmpty || selectedEvents == allSelectableEvents {
            return true
        }

        let selectedEventIDs = selectedEvents.map(\.wcaEventID)
        return selectedEventIDs.allSatisfy { competition.eventIDs.contains($0) }
    }

    private static func matchesStatus(_ competition: CompetitionSummary, status: CompetitionStatusFilter, now: Date) -> Bool {
        let availability = availabilityStatus(for: competition, now: now)
        let futureWaitlist = isFutureWaitlist(for: competition, now: now)
        switch status {
        case .upcoming:
            return availability != .ended
        case .registrationNotOpenYet:
            return availability == .registrationNotOpenYet
                || futureWaitlist
        case .registrationOpen:
            return availability == .registrationOpen
                || (availability == .waitlist && !futureWaitlist)
        case .waitlist:
            return availability == .waitlist
        case .ongoing:
            return availability == .ongoing
        case .ended:
            return availability == .ended
        }
    }

    private static func availabilityStatus(for competition: CompetitionSummary, now: Date) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = calendar.startOfDay(for: competition.startDate)
        let endOfCompetition = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private static func apiDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func yearRange(forOffset offset: Int) -> (start: String, end: String)? {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date()) + offset
        guard let start = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31)) else {
            return nil
        }
        return (apiDateString(from: start), apiDateString(from: end))
    }

    private static func replacingDateBounds(
        existing: [URLQueryItem],
        with range: (start: String, end: String)
    ) -> [URLQueryItem] {
        let filtered = existing.filter { $0.name != "start" && $0.name != "end" }
        return filtered + [
            URLQueryItem(name: "start", value: range.start),
            URLQueryItem(name: "end", value: range.end)
        ]
    }

    private static func acceptLanguageHeader(for languageCode: String) -> String {
        appAcceptLanguageHeader(for: languageCode)
    }

    fileprivate static func loadRecognizedCountriesFromWCA() async throws -> [CompetitionRecognizedCountry] {
        guard let url = URL(string: "https://www.worldcubeassociation.org/regulations/countries/") else {
            throw CompetitionServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("en-US, en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            throw CompetitionServiceError.requestFailed
        }

        let names = parseRecognizedCountryNames(from: html)
        return names.compactMap { name in
            guard let code = countryCode(forRecognizedCountryName: name) else {
                return nil
            }
            return CompetitionRecognizedCountry(code: code, wcaName: name)
        }
    }

    private static func fetchCompetitionPayloadPage(
        queryItems: [URLQueryItem],
        page: Int,
        languageCode: String
    ) async throws -> CompetitionPayloadPage {
        guard var components = URLComponents(string: "https://www.worldcubeassociation.org/api/v0/competitions") else {
            throw CompetitionServiceError.invalidURL
        }

        components.queryItems = queryItems + [URLQueryItem(name: "page", value: String(page))]

        guard let url = components.url else {
            throw CompetitionServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(acceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw CompetitionServiceError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = competitionISO8601Formatter.date(from: value) {
                return date
            }

            if let date = competitionDateOnlyFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported competition date format: \(value)"
            )
        }

        let payloads = try decoder.decode([WCACompetitionPayload].self, from: data)
        let totalCount = httpResponse.value(forHTTPHeaderField: "total").flatMap(Int.init)
        return CompetitionPayloadPage(payloads: payloads, totalCount: totalCount)
    }

    private static func fetchCompetitionNameMapFromCubing(languageCode: String) async -> [String: LocalizedCompetitionInfo] {
        let cubingLanguage = cubingLanguageCode(for: languageCode)
        guard let url = URL(string: "https://cubing.com/competition?lang=\(cubingLanguage)&year=&type=WCA&province=&event=") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let matches = competitionHTMLCaptures(
            in: html,
            pattern: #"(?s)<tr[^>]*>\s*<td[^>]*>.*?</td>\s*<td[^>]*>\s*<a[^>]*class="comp-type-wca"[^>]*href="(?:https://cubing\.com)?/(?:competition|live)/([^"]+)"[^>]*>(.*?)</a>.*?</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>"#
        )

        var lookup: [String: LocalizedCompetitionInfo] = [:]
        for groups in matches {
            guard groups.count >= 5 else { continue }
            let slug = groups[0]
            let localizedName = cleanedCompetitionHTMLText(groups[1])
            let regionPrimary = cleanedCompetitionHTMLText(groups[2])
            let regionSecondary = cleanedCompetitionHTMLText(groups[3])
            let address = cleanedCompetitionHTMLText(groups[4])
            guard !localizedName.isEmpty else { continue }
            lookup[normalizeCompetitionLookupKey(slug)] = LocalizedCompetitionInfo(
                slug: slug,
                name: localizedName,
                regionPrimary: regionPrimary.isEmpty ? nil : regionPrimary,
                regionSecondary: regionSecondary.isEmpty ? nil : regionSecondary,
                address: address.isEmpty ? nil : address,
                registrationStart: nil,
                pauseRegistrationStart: nil,
                reopenRegistration: nil,
                registrationClose: nil
            )
        }

        guard cubingLanguageCode(for: languageCode) == "zh_cn", !lookup.isEmpty else {
            return lookup
        }

        await withTaskGroup(of: (String, CubingCompetitionRegistrationInfo?).self) { group in
            for info in lookup.values {
                guard let slug = info.slug, !slug.isEmpty else { continue }
                group.addTask {
                    (slug, await fetchCompetitionRegistrationInfoFromCubing(slug: slug, languageCode: languageCode))
                }
            }

            for await (slug, registrationInfo) in group {
                guard let registrationInfo else { continue }
                let key = normalizeCompetitionLookupKey(slug)
                guard let existing = lookup[key] else { continue }
                lookup[key] = LocalizedCompetitionInfo(
                    slug: existing.slug,
                    name: existing.name,
                    regionPrimary: existing.regionPrimary,
                    regionSecondary: existing.regionSecondary,
                    address: existing.address,
                    registrationStart: registrationInfo.registrationStart,
                    pauseRegistrationStart: registrationInfo.pauseRegistrationStart,
                    reopenRegistration: registrationInfo.reopenRegistration,
                    registrationClose: registrationInfo.registrationClose
                )
            }
        }

        return lookup
    }

    private static func fetchCompetitionRegistrationInfoFromCubing(
        slug: String,
        languageCode: String
    ) async -> CubingCompetitionRegistrationInfo? {
        let cubingLanguage = cubingLanguageCode(for: languageCode)
        guard let url = URL(string: "https://cubing.com/competition/\(slug)?lang=\(cubingLanguage)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return CubingCompetitionRegistrationInfo(
            registrationStart: extractCubingDetailDate(label: "报名起始时间", in: html),
            pauseRegistrationStart: extractCubingPauseRegistrationStart(in: html),
            reopenRegistration: extractCubingDetailDate(label: "重开报名时间", in: html),
            registrationClose: extractCubingDetailDate(label: "报名结束时间", in: html)
        )
    }

    private static func extractCubingPauseRegistrationStart(in html: String) -> Date? {
        let pattern = #"在([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})至([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})期间暂停报名"#
        guard let capture = firstCompetitionCapture(in: html, pattern: pattern) else {
            return nil
        }
        return cubingCompetitionDateTimeFormatter.date(from: cleanedCompetitionHTMLText(capture))
    }

    private static func extractCubingDetailDate(label: String, in html: String) -> Date? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"(?s)<dt[^>]*>\s*"# + escapedLabel + #"\s*</dt>\s*<dd[^>]*>\s*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})"#
        guard let capture = firstCompetitionCapture(in: html, pattern: pattern) else {
            return nil
        }
        return cubingCompetitionDateTimeFormatter.date(from: cleanedCompetitionHTMLText(capture))
    }

    private static func fetchWCACompetitionDetail(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionDetailContent? {
        guard let url = URL(string: competition.url) else { return nil }
        guard let html = await fetchCompetitionHTML(url: url, languageCode: languageCode) else { return nil }

        async let registerBlocksTask = fetchWCARegisterBlocks(for: competition, languageCode: languageCode)
        async let publicWCIFTask = fetchWCAPublicCompetitors(for: competition, languageCode: languageCode)
        async let competitorsHTMLTask = fetchCompetitionHTML(
            url: URL(string: competition.url + "/registrations"),
            languageCode: languageCode
        )
        let extractedLiveURL = extractWCALiveURL(from: html)
        async let wcaLiveContentTask = fetchWCALiveContent(
            for: competition,
            languageCode: languageCode,
            liveURL: extractedLiveURL
        )

        let noteBlocks = extractWCATabBlocks(from: html)
        let scheduleDays = extractWCAScheduleDays(from: html, languageCode: languageCode)
        let publicWCIFCompetitors = await publicWCIFTask
        let competitorsHTML = await competitorsHTMLTask
        let competitorPreviews = publicWCIFCompetitors.previews.isEmpty
            ? extractWCACompetitorPreviews(from: competitorsHTML)
            : publicWCIFCompetitors.previews
        let competitorsCount = publicWCIFCompetitors.count
            ?? extractWCACompetitorCount(from: html)
            ?? extractWCACompetitorCount(from: competitorsHTML)
        let registerBlocks = await registerBlocksTask
        let liveURLOverride = extractedLiveURL
        let wcaLiveContent = await wcaLiveContentTask

        let liveAvailability: CompetitionLiveAvailability
        if liveURLOverride != nil || wcaLiveContent != nil {
            liveAvailability = availabilityStatus(for: competition, now: Date()) == .ended ? .ended : .available
        } else {
            liveAvailability = wcaLiveAvailability(for: competition)
        }

        return CompetitionDetailContent(
            overviewBlocks: [],
            noteBlocks: noteBlocks,
            travelBlocks: [],
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: false,
            liveAvailability: liveAvailability,
            liveURLOverride: liveURLOverride,
            liveContent: nil,
            wcaLiveContent: wcaLiveContent
        )
    }

    private static func fetchCubingCompetitionDetail(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionDetailContent? {
        guard let slug = competitionSlug(for: competition) else { return nil }
        let cubingLanguage = cubingLanguageCode(for: languageCode)

        async let mainHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let travelHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)/travel?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let scheduleHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)/schedule?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let registerHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)/registration?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let competitorsHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)/competitors?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let liveHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/live/\(slug)?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let sumOfRanksHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/live/\(slug)/statistics/sum-of-ranks?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let podiumsHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/live/\(slug)/podiums?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )

        let main = await mainHTML
        let travel = await travelHTML
        let schedule = await scheduleHTML
        let register = await registerHTML
        let competitors = await competitorsHTML
        let live = await liveHTML
        let sumOfRanks = await sumOfRanksHTML
        let podiums = await podiumsHTML

        guard main != nil || travel != nil || schedule != nil else { return nil }

        let overviewBlocks = main.map(extractCubingOverviewBlocks(from:)) ?? []
        let travelBlocks = travel.map(extractCubingTravelBlocks(from:)) ?? []
        let scheduleDays = schedule.map(extractCubingScheduleDays(from:)) ?? []
        let registerBlocks = register.map(extractCubingRegistrationBlocks(from:)) ?? []
        let registrationRequiresSignIn = register.map(cubingPageRequiresLoginHTML(_:)) ?? false
        let competitorPreviews = extractCubingCompetitorPreviews(from: competitors)
        let competitorsCount = extractCubingCompetitorCount(from: competitors)
            ?? extractCubingCompetitorCount(from: schedule)
            ?? (competitorPreviews.isEmpty ? nil : competitorPreviews.count)
        let liveContent = live.flatMap {
            extractCubingLiveContent(
                from: $0,
                sumOfRanksHTML: sumOfRanks,
                podiumsHTML: podiums
            )
        }

        return CompetitionDetailContent(
            overviewBlocks: overviewBlocks,
            noteBlocks: [],
            travelBlocks: travelBlocks,
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: registrationRequiresSignIn,
            liveAvailability: cubingLiveAvailability(for: competition, liveHTML: live),
            liveURLOverride: nil,
            liveContent: liveContent,
            wcaLiveContent: nil
        )
    }

    private static func fetchCompetitionHTML(
        url: URL?,
        languageCode: String
    ) async -> String? {
        guard let url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return html
    }

    private static func wcaLiveAvailability(for competition: CompetitionSummary) -> CompetitionLiveAvailability {
        switch availabilityStatus(for: competition, now: Date()) {
        case .ongoing:
            return .available
        case .ended:
            return .ended
        case .registrationOpen, .registrationNotOpenYet, .upcoming, .waitlist:
            return .upcoming
        }
    }

    private struct WCAPublicCompetitors {
        let previews: [CompetitionCompetitorPreview]
        let count: Int?
    }

    private struct CubingLiveEventPayload: Decodable {
        let i: String
        let name: String
        let rs: [CubingLiveRoundPayload]
    }

    private struct CubingLiveRoundPayload: Decodable {
        let i: String
        let e: String
        let f: String
        let rn: Int?
        let tt: Int?
        let s: Int?
        let name: String
        let allStatus: [String]?
    }

    private struct CubingLiveParamsPayload: Decodable {
        let e: String
        let r: String
        let filter: String
    }

    private struct CubingLiveFilterPayload: Decodable {
        let label: String
        let value: String
    }

    private struct CubingLiveStaticMessagePayload: Decodable {
        struct User: Decodable {
            let name: String
        }

        let id: String
        let user: User
        let time: Int
        let content: String
    }

    private struct WCAPublicWCIF: Decodable {
        struct Person: Decodable {
            struct Registration: Decodable {
                let eventIds: [String]
                let status: String?
                let isCompeting: Bool?
            }

            struct PersonalBest: Decodable {
                let eventId: String
                let best: Int
                let type: String
                let worldRanking: Int?
                let continentalRanking: Int?
                let nationalRanking: Int?
            }

            let name: String
            let wcaId: String?
            let registrantId: Int?
            let countryIso2: String?
            let gender: String?
            let registration: Registration?
            let personalBests: [PersonalBest]?
        }

        let persons: [Person]
    }

    private struct WCALiveGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let competition: WCALiveCompetitionPayload?
        }

        let data: DataPayload?
    }

    private struct WCALiveCompetitionPayload: Decodable {
        struct CompetitionEvent: Decodable {
            struct Event: Decodable {
                let id: String
                let name: String
            }

            struct Round: Decodable {
                let id: String
                let name: String
                let active: Bool
                let open: Bool
                let number: Int?
            }

            let id: String
            let event: Event
            let rounds: [Round]
        }

        struct Venue: Decodable {
            struct Country: Decodable {
                let iso2: String?
                let name: String?
            }

            struct Room: Decodable {
                struct Activity: Decodable {
                    let id: String
                    let activityCode: String?
                    let name: String
                    let startTime: Date
                    let endTime: Date
                }

                let id: String
                let name: String
                let color: String?
                let activities: [Activity]
            }

            let id: String
            let name: String
            let country: Country?
            let rooms: [Room]
        }

        let id: String
        let name: String
        let wcaId: String?
        let competitionEvents: [CompetitionEvent]
        let venues: [Venue]
    }

    private struct WCALiveResolvedCompetition: Sendable {
        let competitionID: Int
        let finalURL: URL?
    }

    private struct WCALiveRoundGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let round: WCALiveRoundPayload?
        }

        let data: DataPayload?
    }

    private struct WCALiveRoundPayload: Decodable {
        struct CompetitionEventPayload: Decodable {
            struct EventPayload: Decodable {
                let id: String
                let name: String
            }

            let event: EventPayload
        }

        struct FormatPayload: Decodable {
            let id: String
        }

        struct ResultPayload: Decodable {
            struct AttemptPayload: Decodable {
                let result: Int
            }

            struct PersonPayload: Decodable {
                struct CountryPayload: Decodable {
                    let name: String?
                }

                let id: String
                let name: String
                let country: CountryPayload?
            }

            let id: String
            let ranking: Int?
            let best: Int
            let average: Int
            let attempts: [AttemptPayload]
            let person: PersonPayload
        }

        let id: String
        let competitionEvent: CompetitionEventPayload
        let format: FormatPayload
        let results: [ResultPayload]
    }

    private static func fetchWCAPublicCompetitors(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> WCAPublicCompetitors {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(competition.id)/wcif/public") else {
            return WCAPublicCompetitors(previews: [], count: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return WCAPublicCompetitors(previews: [], count: nil)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let wcif = try? decoder.decode(WCAPublicWCIF.self, from: data) else {
            return WCAPublicCompetitors(previews: [], count: nil)
        }

        let acceptedPeople = wcif.persons.filter { person in
            guard let registrantId = person.registrantId, registrantId > 0 else { return false }
            guard let registration = person.registration else { return false }
            if let isCompeting = registration.isCompeting {
                return isCompeting
            }
            return registration.status?.lowercased() == "accepted"
        }

        let previews = acceptedPeople.enumerated().map { index, person in
            CompetitionCompetitorPreview(
                id: "wca-api-competitor-\(index)-\(person.registrantId ?? index)",
                number: person.registrantId.map(String.init),
                name: person.name,
                gender: person.gender,
                subtitle: localizedRegionName(for: person.countryIso2, languageCode: languageCode),
                registeredEventIDs: person.registration?.eventIds ?? []
            )
        }

        return WCAPublicCompetitors(previews: previews, count: acceptedPeople.count)
    }

    private static func fetchWCAPsychPreviews(
        for competition: CompetitionSummary,
        languageCode: String,
        eventID: String?
    ) async -> [CompetitionCompetitorPsychPreview] {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(competition.id)/wcif/public") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let wcif = try? decoder.decode(WCAPublicWCIF.self, from: data) else {
            return []
        }

        let acceptedPeople = wcif.persons.filter { person in
            guard let registrantId = person.registrantId, registrantId > 0 else { return false }
            guard let registration = person.registration else { return false }
            if let isCompeting = registration.isCompeting {
                return isCompeting
            }
            return registration.status?.lowercased() == "accepted"
        }

        let targetEventIDs = resolvedCompetitionPsychEventIDs(
            competitionEventIDs: competition.eventIDs,
            eventID: eventID
        )

        var itemsByCompetitorID: [String: [CompetitionPsychItem]] = [:]
        var namesByCompetitorID: [String: String] = [:]

        for currentEventID in targetEventIDs {
            let rankedPeople = acceptedPeople.compactMap { person -> (personID: String, name: String, best: WCAPublicWCIF.Person.PersonalBest)? in
                guard person.registration?.eventIds.contains(currentEventID) == true,
                      let personalBests = person.personalBests,
                      let preferredBest = preferredWCAPersonalBest(for: currentEventID, in: personalBests) else {
                    return nil
                }

                let personID = person.wcaId ?? "registrant-\(person.registrantId ?? 0)-\(person.name)"
                return (personID, person.name, preferredBest)
            }
            .sorted { lhs, rhs in
                if lhs.best.best != rhs.best.best {
                    return lhs.best.best < rhs.best.best
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            for (index, rankedPerson) in rankedPeople.enumerated() {
                let item = CompetitionPsychItem(
                    id: "\(rankedPerson.personID)-\(currentEventID)",
                    eventID: currentEventID,
                    rank: index + 1,
                    resultText: formattedWCAPsychResult(
                        best: rankedPerson.best.best,
                        eventID: currentEventID,
                        type: rankedPerson.best.type
                    )
                )
                namesByCompetitorID[rankedPerson.personID] = rankedPerson.name
                itemsByCompetitorID[rankedPerson.personID, default: []].append(item)
            }
        }

        return buildCompetitionPsychPreviews(
            itemsByCompetitorID: itemsByCompetitorID,
            namesByCompetitorID: namesByCompetitorID,
            eventOrder: targetEventIDs
        )
    }

    private static func fetchWCALiveContent(
        for competition: CompetitionSummary,
        languageCode: String,
        liveURL: URL?
    ) async -> CompetitionWCALiveContent? {
        guard let resolved = await resolveWCALiveCompetition(for: competition, languageCode: languageCode, liveURL: liveURL) else {
            return nil
        }

        let query = """
        query Competition($id: ID!) {
          competition(id: $id) {
            id
            name
            wcaId
            competitionEvents {
              id
              event { id name }
              rounds { id name active open number }
            }
            venues {
              id
              name
              country { iso2 name }
              rooms {
                id
                name
                color
                activities {
                  id
                  activityCode
                  name
                  startTime
                  endTime
                }
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": String(resolved.competitionID)]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://live.worldcubeassociation.org/api")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let graph = try? decoder.decode(WCALiveGraphQLResponse.self, from: data),
              let payload = graph.data?.competition else {
            return nil
        }

        let rounds = payload.competitionEvents
            .flatMap { event in
                event.rounds.map { round in
                    CompetitionWCALiveRound(
                        id: round.id,
                        eventID: event.event.id,
                        eventName: event.event.name,
                        roundName: round.name,
                        number: round.number,
                        isActive: round.active,
                        isOpen: round.open,
                        results: []
                    )
                }
            }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.isActive ? 0 : (lhs.isOpen ? 1 : 2)
                let rhsPriority = rhs.isActive ? 0 : (rhs.isOpen ? 1 : 2)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if lhs.eventID != rhs.eventID { return lhs.eventID < rhs.eventID }
                return (lhs.number ?? 0) < (rhs.number ?? 0)
            }

        var previewMap: [String: [CompetitionWCALiveResultPreview]] = [:]
        await withTaskGroup(of: (String, [CompetitionWCALiveResultPreview]).self) { group in
            for round in rounds {
                group.addTask {
                    let previews = await fetchWCALiveRoundResultPreviews(
                        roundID: round.id,
                        languageCode: languageCode
                    )
                    return (round.id, previews)
                }
            }

            for await (roundID, previews) in group {
                if !previews.isEmpty {
                    previewMap[roundID] = previews
                }
            }
        }

        let hydratedRounds = rounds.map { round in
            CompetitionWCALiveRound(
                id: round.id,
                eventID: round.eventID,
                eventName: round.eventName,
                roundName: round.roundName,
                number: round.number,
                isActive: round.isActive,
                isOpen: round.isOpen,
                results: previewMap[round.id] ?? []
            )
        }
        .sorted { lhs, rhs in
            let lhsHasPreviews = !lhs.results.isEmpty
            let rhsHasPreviews = !rhs.results.isEmpty
            if lhsHasPreviews != rhsHasPreviews { return lhsHasPreviews && !rhsHasPreviews }

            let lhsPriority = lhs.isActive ? 0 : (lhs.isOpen ? 1 : 2)
            let rhsPriority = rhs.isActive ? 0 : (rhs.isOpen ? 1 : 2)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.eventID != rhs.eventID { return lhs.eventID < rhs.eventID }
            return (lhs.number ?? 0) < (rhs.number ?? 0)
        }

        let now = Date()
        let venues = payload.venues.map { venue in
            CompetitionWCALiveVenue(
                id: venue.id,
                name: venue.name,
                countryName: venue.country?.name,
                rooms: venue.rooms.map { room in
                    let sortedActivities = room.activities.sorted { $0.startTime < $1.startTime }
                    let currentActivity = sortedActivities.first(where: { $0.startTime <= now && $0.endTime >= now })
                    let nextActivity = currentActivity == nil
                        ? sortedActivities.first(where: { $0.startTime > now })
                        : nil
                    return CompetitionWCALiveRoom(
                        id: room.id,
                        name: room.name,
                        currentActivityName: currentActivity?.name,
                        currentActivityStart: currentActivity?.startTime,
                        currentActivityEnd: currentActivity?.endTime,
                        nextActivityName: nextActivity?.name,
                        nextActivityStart: nextActivity?.startTime
                    )
                }
            )
        }

        let eventIDs = Array(Set(payload.competitionEvents.map { $0.event.id })).sorted()

        return CompetitionWCALiveContent(
            competitionID: resolved.competitionID,
            eventIDs: eventIDs,
            rounds: hydratedRounds,
            venues: venues
        )
    }

    private static func fetchWCALiveRoundResultPreviews(
        roundID: String,
        languageCode: String
    ) async -> [CompetitionWCALiveResultPreview] {
        let query = """
        query Round($id: ID!) {
          round(id: $id) {
            id
            format { id }
            competitionEvent { event { id name } }
            results {
              id
              ranking
              best
              average
              attempts { result }
              person {
                id
                name
                country { name }
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": roundID]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return []
        }

        var request = URLRequest(url: URL(string: "https://live.worldcubeassociation.org/api")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            return []
        }

        let decoder = JSONDecoder()
        guard let graph = try? decoder.decode(WCALiveRoundGraphQLResponse.self, from: data),
              let round = graph.data?.round else {
            return []
        }

        return round.results
            .compactMap { result in
                guard let ranking = result.ranking, ranking > 0 else { return nil }
                return CompetitionWCALiveResultPreview(
                    id: result.id,
                    ranking: ranking,
                    name: result.person.name,
                    region: result.person.country?.name,
                    attempts: result.attempts.map(\.result),
                    best: result.best,
                    average: result.average
                )
            }
            .sorted { lhs, rhs in
                if lhs.ranking != rhs.ranking { return lhs.ranking < rhs.ranking }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { $0 }
    }

    private static func resolveWCALiveCompetition(
        for competition: CompetitionSummary,
        languageCode: String,
        liveURL: URL?
    ) async -> WCALiveResolvedCompetition? {
        if let liveURL,
           let competitionID = extractWCALiveCompetitionID(from: liveURL) {
            return WCALiveResolvedCompetition(competitionID: competitionID, finalURL: liveURL)
        }

        guard let liveURL = liveURL ?? URL(string: "https://live.worldcubeassociation.org/link/competitions/\(competition.id)") else {
            return nil
        }

        var request = URLRequest(url: liveURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let finalURL = response.url,
              let competitionID = extractWCALiveCompetitionID(from: finalURL) else {
            return nil
        }

        return WCALiveResolvedCompetition(competitionID: competitionID, finalURL: finalURL)
    }

    private static func extractWCALiveCompetitionID(from url: URL) -> Int? {
        guard let capture = firstCompetitionCapture(
            in: url.absoluteString,
            pattern: #"/competitions/([0-9]+)"#
        ) else {
            return nil
        }
        return Int(capture)
    }

    private static func localizedRegionName(for iso2: String?, languageCode: String) -> String? {
        guard let iso2, !iso2.isEmpty else { return nil }
        let locale = appLocale(for: languageCode)
        return locale.localizedString(forRegionCode: iso2) ?? iso2
    }

    private static func extractCubingLiveContent(
        from html: String,
        sumOfRanksHTML: String?,
        podiumsHTML: String?
    ) -> CompetitionLiveContent? {
        guard !cubingPageRequiresLoginHTML(html), !cubingPageNotFoundHTML(html) else { return nil }

        guard
            let competitionIDString = firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-c=\"([0-9]+)\""#),
            let competitionID = Int(competitionIDString),
            let eventsJSON = firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-events=\"([^\"]+)\""#),
            let paramsJSON = firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-params=\"([^\"]+)\""#),
            let filtersJSON = firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-filters=\"([^\"]+)\""#)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        guard
            let decodedEventsData = decodeCompetitionHTMLEntities(eventsJSON).data(using: .utf8),
            let decodedParamsData = decodeCompetitionHTMLEntities(paramsJSON).data(using: .utf8),
            let decodedFiltersData = decodeCompetitionHTMLEntities(filtersJSON).data(using: .utf8),
            let eventPayloads = try? decoder.decode([CubingLiveEventPayload].self, from: decodedEventsData),
            let paramsPayload = try? decoder.decode(CubingLiveParamsPayload.self, from: decodedParamsData),
            let filterPayloads = try? decoder.decode([CubingLiveFilterPayload].self, from: decodedFiltersData)
        else {
            return nil
        }

        let staticMessagePayloads: [CubingLiveStaticMessagePayload]
        if let staticMessagesJSON = firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-static-messages=\"([^\"]+)\""#),
           let decodedStaticMessagesData = decodeCompetitionHTMLEntities(staticMessagesJSON).data(using: .utf8),
           let payloads = try? decoder.decode([CubingLiveStaticMessagePayload].self, from: decodedStaticMessagesData) {
            staticMessagePayloads = payloads
        } else {
            staticMessagePayloads = []
        }

        let roundOptions = eventPayloads.flatMap { event in
            event.rs.map { round in
                let statusText: String?
                if let statuses = round.allStatus,
                   let statusIndex = round.s,
                   statuses.indices.contains(statusIndex),
                   statusIndex != 0 {
                    statusText = statuses[statusIndex]
                } else {
                    statusText = nil
                }

                return CompetitionLiveRoundOption(
                    id: "\(event.i)|\(round.i)",
                    eventID: event.i,
                    roundID: round.i,
                    eventName: event.name,
                    roundName: round.name,
                    statusText: statusText,
                    recordedCount: round.rn ?? 0,
                    totalCount: round.tt ?? 0,
                    formatID: round.f
                )
            }
        }

        let filterOptions = filterPayloads.map {
            CompetitionLiveFilterOption(id: $0.value, label: $0.label)
        }

        let staticMessages = staticMessagePayloads.map { payload in
            CompetitionLiveStaticMessage(
                id: payload.id,
                author: payload.user.name,
                timestamp: payload.time,
                text: cleanedCompetitionHTMLText(payload.content),
                linkURL: firstCompetitionCapture(
                    in: decodeCompetitionHTMLEntities(payload.content),
                    pattern: #"href=\"([^\"]+)\""#
                ).flatMap(URL.init(string:))
            )
        }

        return CompetitionLiveContent(
            competitionID: competitionID,
            sourceType: firstCompetitionCapture(in: html, pattern: #"id=\"live-container\"[^>]*data-type=\"([^\"]+)\""#) ?? "",
            roundOptions: roundOptions,
            filterOptions: filterOptions,
            defaultEventID: paramsPayload.e,
            defaultRoundID: paramsPayload.r,
            defaultFilterValue: paramsPayload.filter,
            staticMessages: staticMessages,
            sumOfRanksURL: firstCompetitionCapture(in: html, pattern: #"href=\"([^\"]+/statistics/sum-of-ranks)\""#)
                .flatMap(URL.init(string:)),
            podiumsURL: firstCompetitionCapture(in: html, pattern: #"href=\"([^\"]+/podiums)\""#)
                .flatMap(URL.init(string:)),
            sumOfRanksContent: extractCubingSumOfRanksContent(from: sumOfRanksHTML),
            podiumSections: extractCubingPodiumSections(from: podiumsHTML)
        )
    }

    private static func extractCubingSumOfRanksContent(from html: String?) -> CompetitionLiveSumOfRanksContent? {
        guard let html, !cubingPageRequiresLoginHTML(html), !cubingPageNotFoundHTML(html) else { return nil }

        let eventIDs = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<input[^>]*value=\"([a-z0-9]+)\"[^>]*checked=\"checked\"[^>]*>"#
        )
        .compactMap(\.first)

        guard let tbodyHTML = firstCompetitionCapture(in: html, pattern: #"(?is)<tbody>(.*?)</tbody>"#) else {
            return nil
        }

        let rowCaptures = competitionHTMLCaptures(in: tbodyHTML, pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#)
        let entries = rowCaptures.compactMap { capture -> CompetitionLiveSumOfRanksEntry? in
            guard let rowHTML = capture.first else { return nil }
            let cellHTMLs = competitionHTMLCaptures(in: rowHTML, pattern: #"(?is)<td[^>]*>(.*?)</td>"#).compactMap(\.first)
            let cells = cellHTMLs.map { cleanedCompetitionHTMLText($0) }
            guard cells.count >= 4 else { return nil }

            let placeText = cells[0]
            let name = cells[1]
            let region = cells[2]
            let totalText = cells[3]
            guard !name.isEmpty else { return nil }

            let itemTexts = Array(cells.dropFirst(4))
            let items = zip(eventIDs, itemTexts).compactMap { eventID, rankText -> CompetitionLiveSumOfRanksItem? in
                let trimmed = rankText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return CompetitionLiveSumOfRanksItem(
                    id: "\(name)-\(eventID)-\(trimmed)",
                    eventID: eventID,
                    rankText: trimmed
                )
            }

            return CompetitionLiveSumOfRanksEntry(
                id: "\(name)-\(placeText)-\(totalText)",
                placeText: placeText,
                name: name,
                region: region,
                totalText: totalText,
                items: items
            )
        }

        return CompetitionLiveSumOfRanksContent(eventIDs: eventIDs, entries: entries)
    }

    private static func extractCubingPodiumSections(from html: String?) -> [CompetitionLivePodiumSection] {
        guard let html, !cubingPageRequiresLoginHTML(html), !cubingPageNotFoundHTML(html) else { return [] }

        let sectionCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)(?:<h[23][^>]*>(.*?)</h[23]>\s*)?<div class=\"table-responsive\"[^>]*>\s*<table[^>]*>(.*?)</table>"#
        )

        return sectionCaptures.compactMap { capture -> CompetitionLivePodiumSection? in
            guard capture.count >= 2 else { return nil }
            let rawTitle = cleanedCompetitionHTMLText(capture[0])
            let tableHTML = capture[1]
            guard let tbodyHTML = firstCompetitionCapture(in: tableHTML, pattern: #"(?is)<tbody>(.*?)</tbody>"#) else {
                return nil
            }

            let rowCaptures = competitionHTMLCaptures(in: tbodyHTML, pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#)
            let placements = rowCaptures.compactMap { rowCapture -> CompetitionLivePodiumPlacement? in
                guard let rowHTML = rowCapture.first else { return nil }
                let cellHTMLs = competitionHTMLCaptures(in: rowHTML, pattern: #"(?is)<td[^>]*>(.*?)</td>"#).compactMap(\.first)
                let cells = cellHTMLs.map { cleanedCompetitionHTMLText($0) }
                guard cells.count >= 5 else { return nil }
                let name = cells[1]
                guard !name.isEmpty, name != "没有找到数据." else { return nil }

                return CompetitionLivePodiumPlacement(
                    id: "\(rawTitle)-\(cells[0])-\(name)",
                    placeText: cells[0],
                    name: name,
                    bestText: cells[2],
                    averageText: cells[3],
                    region: cells[4]
                )
            }

            if rawTitle.isEmpty && placements.isEmpty {
                return nil
            }

            return CompetitionLivePodiumSection(
                id: rawTitle.isEmpty ? UUID().uuidString : rawTitle,
                title: rawTitle.isEmpty ? nil : rawTitle,
                placements: placements
            )
        }
    }

    private static func cubingLiveAvailability(
        for competition: CompetitionSummary,
        liveHTML: String?
    ) -> CompetitionLiveAvailability {
        if let liveHTML, !cubingPageRequiresLoginHTML(liveHTML), !cubingPageNotFoundHTML(liveHTML) {
            return .available
        }

        switch availabilityStatus(for: competition, now: Date()) {
        case .ongoing:
            return .unavailable
        case .ended:
            return .ended
        case .registrationOpen, .registrationNotOpenYet, .upcoming, .waitlist:
            return .upcoming
        }
    }

    private static func fetchWCARegisterBlocks(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> [CompetitionDetailTextBlock] {
        guard let url = URL(string: competition.url + "/register"),
              let html = await fetchCompetitionHTML(url: url, languageCode: languageCode) else {
            return []
        }

        return extractWCARegisterBlocks(from: html, languageCode: languageCode)
    }

    private static func competitionSlug(for competition: CompetitionSummary) -> String? {
        [competition.website, competition.url, competition.id]
            .compactMap { $0 }
            .compactMap { value in
                value
                    .replacingOccurrences(of: #"^https?://cubing\.com/competition/"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
                    .components(separatedBy: "/").first?
                    .components(separatedBy: "?").first
            }
            .first { !$0.isEmpty }
    }

    private static func extractWCATabBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        let captures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?s)<div class=\"tab-pane\" id=\"[^\"]*-([^\"]+)\">(.*?)</div>"#
        )

        return captures.compactMap { capture in
            guard capture.count >= 2 else { return nil }
            let rawID = capture[0]
            let body = cleanedCompetitionHTMLText(capture[1])
            guard !body.isEmpty else { return nil }
            let title = rawID
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return CompetitionDetailTextBlock(
                id: "wca-\(rawID)",
                title: title,
                body: body
            )
        }
    }

    private static func extractWCARegisterBlocks(from html: String, languageCode: String) -> [CompetitionDetailTextBlock] {
        var blocks: [CompetitionDetailTextBlock] = []

        if let requirementsHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?s)<p><b>Registration requirements for the competition:</b>\s*</p>(.*?)(?:<h2>|<hr/>)"#
        ) {
            let body = cleanedCompetitionHTMLText(requirementsHTML)
            if !body.isEmpty {
                blocks.append(
                    CompetitionDetailTextBlock(
                        id: "wca-register-requirements",
                        title: localizedCompetitionString(
                            key: "competitions.detail.registration_requirements_title",
                            languageCode: languageCode
                        ),
                        body: body
                    )
                )
            }
        }

        let sectionCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?s)<h2>(.*?)</h2>\s*(.*?)(?=<h2>|<hr/>)"#
        )

        for (index, capture) in sectionCaptures.enumerated() {
            guard capture.count >= 2 else { continue }
            let title = cleanedCompetitionHTMLText(capture[0])
            let body = cleanedCompetitionHTMLText(capture[1])
            guard !body.isEmpty else { continue }
            blocks.append(
                CompetitionDetailTextBlock(
                    id: "wca-register-\(index)",
                    title: title.isEmpty ? nil : title,
                    body: body
                )
            )
        }

        return blocks
    }

    private static func extractWCALiveURL(from html: String) -> URL? {
        let patterns = [
            #"href=['"]((?:https://live\.worldcubeassociation\.org|https://www\.worldcubeassociation\.org)?/link/competitions/[^'"]+)['"]"#,
            #"href=['"]((?:https://live\.worldcubeassociation\.org|https://www\.worldcubeassociation\.org)/competitions/[0-9]+[^'"]*)['"]"#
        ]

        for pattern in patterns {
            guard let capture = firstCompetitionCapture(in: html, pattern: pattern), !capture.isEmpty else { continue }

            if capture.hasPrefix("http://") || capture.hasPrefix("https://") {
                return URL(string: capture)
            }

            if capture.hasPrefix("/link/") || capture.hasPrefix("/competitions/") {
                return URL(string: "https://www.worldcubeassociation.org\(capture)")
            }
        }

        return nil
    }

    private static func extractWCACompetitorCount(from html: String?) -> Int? {
        guard let html else { return nil }

        let countPatterns = [
            #"(?is)<dt[^>]*>\s*Competitors\s*</dt>\s*<dd[^>]*>\s*([0-9]+)"#,
            #"(?is)>\s*Competitors\s*<.*?>\s*([0-9]+)\s*<"#,
            #"(?i)\b([0-9]+)\s+competitors\b"#
        ]

        for pattern in countPatterns {
            if let capture = firstCompetitionCapture(in: html, pattern: pattern),
               let value = Int(cleanedCompetitionHTMLText(capture)) {
                return value
            }
        }

        return nil
    }

    private static func extractWCACompetitorPreviews(from html: String?) -> [CompetitionCompetitorPreview] {
        guard let html else { return [] }

        let rowCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#
        )

        var previews: [CompetitionCompetitorPreview] = []
        var seen: Set<String> = []

        for rowCapture in rowCaptures {
            guard let rowHTML = rowCapture.first else { continue }

            let cellCaptures = competitionHTMLCaptures(
                in: rowHTML,
                pattern: #"(?is)<t[dh][^>]*>(.*?)</t[dh]>"#
            )
            let rawCells = cellCaptures.compactMap(\.first)
            let cells = rawCells.map { cleanedCompetitionHTMLText($0) }
            guard cells.count >= 3 else { continue }

            let candidateNameIndex: Int
            if competitionLooksLikePersonNameHTML(cells[0]) {
                candidateNameIndex = 0
            } else if cells.count > 1, competitionLooksLikePersonNameHTML(cells[1]) {
                candidateNameIndex = 1
            } else if cells.count > 2, competitionLooksLikePersonNameHTML(cells[2]) {
                candidateNameIndex = 2
            } else {
                continue
            }

            let name = cells[candidateNameIndex]
            let region = cells.indices.contains(candidateNameIndex + 1) ? cells[candidateNameIndex + 1] : ""
            guard competitionLooksLikePersonNameHTML(name), seen.insert(name).inserted else { continue }

            let rawEventCells = Array(rawCells.dropFirst(candidateNameIndex + 2).dropLast())
            let registeredEventIDs = inferRegisteredEventIDs(fromHTMLCells: rawEventCells, orderedEventIDs: competitionSelectableEventIDs())

            previews.append(
                CompetitionCompetitorPreview(
                    id: "wca-competitor-\(previews.count)",
                    number: candidateNameIndex > 0 ? cells[0] : nil,
                    name: name,
                    gender: nil,
                    subtitle: region.isEmpty ? nil : region,
                    registeredEventIDs: registeredEventIDs
                )
            )
        }

        if !previews.isEmpty {
            return previews
        }

        let fallbackCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<a[^>]*href=\"/persons/[^\"]+\"[^>]*>(.*?)</a>"#
        )

        return fallbackCaptures.compactMap { capture in
            guard let rawName = capture.first else { return nil }
            let name = cleanedCompetitionHTMLText(rawName)
            guard competitionLooksLikePersonNameHTML(name) else { return nil }
            return CompetitionCompetitorPreview(
                id: "wca-competitor-fallback-\(name)",
                number: nil,
                name: name,
                gender: nil,
                subtitle: nil,
                registeredEventIDs: []
            )
        }
    }

    private static func extractWCAScheduleDays(from html: String, languageCode: String) -> [CompetitionScheduleDay] {
        guard let propsHTML = firstCompetitionCapture(
            in: html,
            pattern: #"data-react-class=\"Schedule\"[^>]*data-react-props=\"([^\"]+)\""#
        ) else {
            return []
        }

        let jsonString = decodeCompetitionHTMLEntities(propsHTML)
        guard let data = jsonString.data(using: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let props = try? decoder.decode(WCAScheduleProps.self, from: data) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = appLocale(for: languageCode)
        formatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = appLocale(for: languageCode)
        timeFormatter.dateFormat = "HH:mm"

        var grouped: [String: [CompetitionScheduleEntry]] = [:]

        for venue in props.wcif.schedule.venues {
            for room in venue.rooms {
                for activity in room.activities {
                    let dateKey = formatter.string(from: activity.startTime)
                    let timeText = "\(timeFormatter.string(from: activity.startTime))–\(timeFormatter.string(from: activity.endTime))"
                    let detailText = room.name == venue.name ? room.name : "\(venue.name) · \(room.name)"
                    grouped[dateKey, default: []].append(
                        CompetitionScheduleEntry(
                            id: "\(activity.id)",
                            timeText: timeText,
                            title: activity.name,
                            detailText: detailText
                        )
                    )
                }
            }
        }

        return grouped.keys.sorted().map { key in
            CompetitionScheduleDay(
                id: "wca-\(key)",
                title: key,
                entries: grouped[key, default: []].sorted { lhs, rhs in lhs.timeText < rhs.timeText }
            )
        }
    }

    private static func extractCubingOverviewBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        var blocks: [CompetitionDetailTextBlock] = []

        if let aboutHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?s)<dt[^>]*>\s*About the Competition\s*</dt>\s*<dd[^>]*>(.*?)</dd>"#
        ) {
            let body = cleanedCompetitionHTMLText(aboutHTML)
            if !body.isEmpty {
                blocks.append(CompetitionDetailTextBlock(id: "cubing-about", title: nil, body: body))
            }
        }

        if let noteHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?s)<dd[^>]*>\s*(This competition is recognized as an official World Cube Association.*?)(?:</dd>|<dt)"#
        ) {
            let body = cleanedCompetitionHTMLText(noteHTML)
            if !body.isEmpty {
                blocks.append(CompetitionDetailTextBlock(id: "cubing-note", title: nil, body: body))
            }
        }

        return blocks
    }

    private static func extractCubingTravelBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        var blocks: [CompetitionDetailTextBlock] = []

        if let travelHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?s)<dt[^>]*>\s*Travel Info\s*</dt>\s*<dd[^>]*>(.*?)</dd>"#
        ) {
            let captures = competitionHTMLCaptures(
                in: travelHTML,
                pattern: #"(?s)<h[34][^>]*>(.*?)</h[34]>\s*(.*?)(?=<h[34][^>]*>|$)"#
            )

            let extractedBlocks = captures.compactMap { capture -> CompetitionDetailTextBlock? in
                guard capture.count >= 2 else { return nil }
                let title = cleanedCompetitionHTMLText(capture[0])
                let body = cleanedCompetitionHTMLText(capture[1])
                guard !body.isEmpty else { return nil }
                return CompetitionDetailTextBlock(
                    id: "cubing-travel-\(blocks.count)-\(title)",
                    title: title.isEmpty ? nil : title,
                    body: body
                )
            }

            if !extractedBlocks.isEmpty {
                blocks.append(contentsOf: extractedBlocks)
            } else {
                let body = cleanedCompetitionHTMLText(travelHTML)
                if !body.isEmpty {
                    blocks.append(CompetitionDetailTextBlock(id: "cubing-travel", title: nil, body: body))
                }
            }
        }

        return blocks
    }

    private static func extractCubingRegistrationBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        guard !cubingPageRequiresLoginHTML(html) else { return [] }

        if let summaryHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?s)<div class=\"page-content\">(.*?)</div>\s*</div>\s*</div>"#
        ) {
            let body = cleanedCompetitionHTMLText(summaryHTML)
            if !body.isEmpty {
                return [CompetitionDetailTextBlock(id: "cubing-registration", title: nil, body: body)]
            }
        }

        return []
    }

    private static func extractCubingCompetitorPreviews(from html: String?) -> [CompetitionCompetitorPreview] {
        guard let html, !cubingPageRequiresLoginHTML(html), !cubingPageNotFoundHTML(html) else { return [] }
        let eventColumnIDs = extractCubingEventColumnIDsHTML(from: html)

        let rowCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#
        )

        var previews: [CompetitionCompetitorPreview] = []
        var seen: Set<String> = []
        for rowCapture in rowCaptures {
            guard let rowHTML = rowCapture.first else { continue }
            let cellCaptures = competitionHTMLCaptures(
                in: rowHTML,
                pattern: #"(?is)<td[^>]*>(.*?)</td>"#
            )
            let rawCells = cellCaptures.compactMap(\.first)
            let cells = rawCells.map { cleanedCompetitionHTMLText($0) }
            guard cells.count >= 4 else { continue }

            let number = cells[0]
            let name = cells[1]
            let gender = cells[2]
            let region = cells[3]
            guard competitionLooksLikePersonNameHTML(name), seen.insert(name).inserted else { continue }

            let rawEventCells = Array(rawCells.dropFirst(4))
            let registeredEventIDs = inferRegisteredEventIDs(fromHTMLCells: rawEventCells, orderedEventIDs: eventColumnIDs)

            previews.append(
                CompetitionCompetitorPreview(
                    id: "cubing-competitor-\(previews.count)",
                    number: number.isEmpty ? nil : number,
                    name: name,
                    gender: gender.isEmpty ? nil : gender,
                    subtitle: region.isEmpty ? nil : region,
                    registeredEventIDs: registeredEventIDs
                )
            )
        }

        return previews
    }

    private static func fetchCubingPsychPreviews(
        for competition: CompetitionSummary,
        languageCode: String,
        eventID: String?
    ) async -> [CompetitionCompetitorPsychPreview] {
        guard let slug = competitionSlug(for: competition) else { return [] }
        let cubingLanguage = cubingLanguageCode(for: languageCode)
        let targetEventIDs = resolvedCompetitionPsychEventIDs(
            competitionEventIDs: competition.eventIDs,
            eventID: eventID
        )

        var itemsByCompetitorID: [String: [CompetitionPsychItem]] = [:]
        var namesByCompetitorID: [String: String] = [:]

        for currentEventID in targetEventIDs {
            guard let psychURL = URL(
                string: "https://cubing.com/competition/\(slug)/competitors?lang=\(cubingLanguage)&sort=\(currentEventID)"
            ),
            let html = await fetchCompetitionHTML(url: psychURL, languageCode: languageCode) else {
                continue
            }

            let previews = extractCubingPsychPreviews(from: html, eventID: currentEventID)
            for preview in previews {
                namesByCompetitorID[preview.id] = preview.name
                itemsByCompetitorID[preview.id, default: []].append(contentsOf: preview.items)
            }
        }

        return buildCompetitionPsychPreviews(
            itemsByCompetitorID: itemsByCompetitorID,
            namesByCompetitorID: namesByCompetitorID,
            eventOrder: targetEventIDs
        )
    }

    nonisolated private static func extractCubingPsychPreviews(
        from html: String?,
        eventID: String
    ) -> [CompetitionCompetitorPsychPreview] {
        guard let html,
              !cubingPageRequiresLoginHTML(html),
              !cubingPageNotFoundHTML(html) else { return [] }

        let orderedEventIDs = extractCubingEventColumnIDsHTML(from: html)
        let rowCaptures = competitionHTMLCaptures(in: html, pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#)
        guard let eventColumnIndex = orderedEventIDs.firstIndex(of: eventID) else { return [] }

        var previews: [CompetitionCompetitorPsychPreview] = []
        var seen: Set<String> = []

        for rowCapture in rowCaptures {
            guard let rowHTML = rowCapture.first else { continue }
            let cellCaptures = competitionHTMLCaptures(in: rowHTML, pattern: #"(?is)<td[^>]*>(.*?)</td>"#)
            let rawCells = cellCaptures.compactMap(\.first)
            let cells = rawCells.map { cleanedCompetitionHTMLText($0) }
            guard cells.count >= 4 else { continue }

            let number = cells[0]
            let name = cells[1]
            guard competitionLooksLikePersonNameHTML(name) else { continue }
            let competitorID = cubingCompetitorIdentifierHTML(number: number, nameCellHTML: rawCells[1], name: name)
            guard seen.insert(competitorID).inserted else { continue }

            let targetCellIndex = 4 + eventColumnIndex
            guard rawCells.indices.contains(targetCellIndex),
                  let psychItem = extractCubingPsychItem(from: rawCells[targetCellIndex], eventID: eventID, competitorID: competitorID) else {
                continue
            }

            previews.append(
                CompetitionCompetitorPsychPreview(
                    id: competitorID,
                    name: name,
                    items: [psychItem]
                )
            )
        }

        return previews
    }

    nonisolated private static func extractCubingPsychItem(
        from cellHTML: String,
        eventID: String,
        competitorID: String
    ) -> CompetitionPsychItem? {
        let cleaned = cleanedCompetitionHTMLText(cellHTML)
        let nsCleaned = cleaned as NSString
        let range = NSRange(location: 0, length: nsCleaned.length)
        guard
            let regex = try? NSRegularExpression(pattern: #"^\[(\d+)\]\s*(.+)$"#),
            let match = regex.firstMatch(in: cleaned, options: [], range: range),
            match.numberOfRanges == 3,
            let rank = Int(nsCleaned.substring(with: match.range(at: 1)))
        else {
            return nil
        }

        let resultText = nsCleaned.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resultText.isEmpty else { return nil }

        return CompetitionPsychItem(
            id: "\(competitorID)-\(eventID)",
            eventID: eventID,
            rank: rank,
            resultText: resultText
        )
    }

    private static func inferRegisteredEventIDs(fromHTMLCells cells: [String], orderedEventIDs: [String]) -> [String] {
        return zip(cells, orderedEventIDs).compactMap { cellHTML, eventID in
            isRegisteredCompetitionCell(cellHTML) ? eventID : nil
        }
    }

    private static func resolvedCompetitionPsychEventIDs(
        competitionEventIDs: [String],
        eventID: String?
    ) -> [String] {
        if let eventID, !eventID.isEmpty {
            return competitionEventIDs.contains(eventID) ? [eventID] : []
        }

        let ordered = competitionSelectableEventIDs()
        return ordered.filter { competitionEventIDs.contains($0) }
    }

    private static func preferredWCAPersonalBest(
        for eventID: String,
        in personalBests: [WCAPublicWCIF.Person.PersonalBest]
    ) -> WCAPublicWCIF.Person.PersonalBest? {
        let filtered = personalBests.filter { $0.eventId == eventID && $0.best > 0 }
        if let average = filtered.first(where: { $0.type == "average" }) {
            return average
        }
        return filtered.first(where: { $0.type == "single" })
    }

    private static func buildCompetitionPsychPreviews(
        itemsByCompetitorID: [String: [CompetitionPsychItem]],
        namesByCompetitorID: [String: String],
        eventOrder: [String]
    ) -> [CompetitionCompetitorPsychPreview] {
        let eventIndexMap = Dictionary(uniqueKeysWithValues: eventOrder.enumerated().map { ($1, $0) })

        return itemsByCompetitorID.compactMap { competitorID, items in
            guard let name = namesByCompetitorID[competitorID], !items.isEmpty else { return nil }
            let sortedItems = items.sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return (eventIndexMap[lhs.eventID] ?? .max) < (eventIndexMap[rhs.eventID] ?? .max)
            }
            return CompetitionCompetitorPsychPreview(
                id: competitorID,
                name: name,
                items: sortedItems
            )
        }
        .sorted { lhs, rhs in
            let lhsBestRank = lhs.items.map(\.rank).min() ?? .max
            let rhsBestRank = rhs.items.map(\.rank).min() ?? .max
            if lhsBestRank != rhsBestRank {
                return lhsBestRank < rhsBestRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func topCuberTier(for personalBest: WCAPublicWCIF.Person.PersonalBest) -> CompetitionTopCuberTier? {
        if personalBest.worldRanking == 1 {
            return .wr
        }
        if personalBest.continentalRanking == 1 {
            return .cr
        }
        if personalBest.nationalRanking == 1 {
            return .nr
        }
        return nil
    }

    private static func topCuberTierPriority(_ tier: CompetitionTopCuberTier) -> Int {
        switch tier {
        case .wr: return 0
        case .cr: return 1
        case .nr: return 2
        }
    }

    private static func mergeTopCuberBadges(
        existing: [CompetitionTopCuberBadge],
        incoming: [CompetitionTopCuberBadge]
    ) -> [CompetitionTopCuberBadge] {
        var bestTierByEvent: [String: CompetitionTopCuberTier] = [:]

        for badge in existing + incoming {
            let current = bestTierByEvent[badge.eventID]
            if let current {
                if topCuberTierPriority(badge.tier) < topCuberTierPriority(current) {
                    bestTierByEvent[badge.eventID] = badge.tier
                }
            } else {
                bestTierByEvent[badge.eventID] = badge.tier
            }
        }

        return bestTierByEvent.map { eventID, tier in
            CompetitionTopCuberBadge(id: "\(eventID)-\(tier.rawValue)", eventID: eventID, tier: tier)
        }
    }

    private static func formattedWCAPsychResult(best: Int, eventID: String, type: String) -> String {
        switch eventID {
        case "333fm":
            if type == "average" {
                return String(format: "%.2f", Double(best) / 100.0)
            }
            return "\(best)"
        case "333mbf":
            return "\(best)"
        default:
            return formattedWCATimeFromCentiseconds(best)
        }
    }

    private static func formattedWCATimeFromCentiseconds(_ centiseconds: Int) -> String {
        guard centiseconds > 0 else { return "—" }
        let minutes = centiseconds / 6000
        let seconds = (centiseconds % 6000) / 100
        let hundredths = centiseconds % 100

        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
        }
        return String(format: "%d.%02d", seconds, hundredths)
    }

    private static func isRegisteredCompetitionCell(_ html: String) -> Bool {
        let trimmedHTML = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHTML.isEmpty else { return false }

        if trimmedHTML.localizedCaseInsensitiveContains("<img")
            || trimmedHTML.localizedCaseInsensitiveContains("<svg")
            || trimmedHTML.localizedCaseInsensitiveContains("glyphicon")
            || trimmedHTML.localizedCaseInsensitiveContains("icon-")
            || trimmedHTML.localizedCaseInsensitiveContains("fa-") {
            return true
        }

        let cleaned = cleanedCompetitionHTMLText(trimmedHTML)
        guard !cleaned.isEmpty else { return false }
        if cleaned == "-" || cleaned == "—" || cleaned == "–" {
            return false
        }
        return true
    }

    private static func extractCubingCompetitorCount(from html: String?) -> Int? {
        guard let html else { return nil }
        if !cubingPageRequiresLoginHTML(html), !cubingPageNotFoundHTML(html) {
            let rowCaptures = competitionHTMLCaptures(
                in: html,
                pattern: #"(?is)<tr[^>]*>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>"#
            )
            let names = rowCaptures.compactMap { row -> String? in
                guard row.count >= 4 else { return nil }
                let name = cleanedCompetitionHTMLText(row[1])
                return competitionLooksLikePersonNameHTML(name) ? name : nil
            }
            if !names.isEmpty {
                return Set(names).count
            }
        }
        let captures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?s)<tr[^>]*>\s*<td>.*?</td><td>.*?</td><td>.*?</td><td>.*?</td><td>.*?</td><td>.*?</td><td>.*?</td><td>([0-9]+)</td>\s*</tr>"#
        )
        let values = captures.compactMap { Int($0.first ?? "") }
        return values.max()
    }

    private static func extractCubingScheduleDays(from html: String) -> [CompetitionScheduleDay] {
        let sections = competitionHTMLCaptures(
            in: html,
            pattern: #"(?s)<h3 class=\"panel-title\">(.*?)</h3>.*?<tbody>(.*?)</tbody>"#
        )

        return sections.compactMap { capture in
            guard capture.count >= 2 else { return nil }
            let title = cleanedCompetitionHTMLText(capture[0])
            let rowCaptures = competitionHTMLCaptures(
                in: capture[1],
                pattern: #"(?s)<tr[^>]*>\s*<td>(.*?)</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td><td>(.*?)</td>\s*</tr>"#
            )
            let entries = rowCaptures.enumerated().compactMap { index, row -> CompetitionScheduleEntry? in
                guard row.count >= 8 else { return nil }
                let start = cleanedCompetitionHTMLText(row[0])
                let end = cleanedCompetitionHTMLText(row[1])
                let event = cleanedCompetitionHTMLText(row[2])
                let round = cleanedCompetitionHTMLText(row[3])
                let format = cleanedCompetitionHTMLText(row[4])
                let cutoff = cleanedCompetitionHTMLText(row[5])
                let timeLimit = cleanedCompetitionHTMLText(row[6])

                var details: [String] = []
                if !round.isEmpty { details.append(round) }
                if !format.isEmpty { details.append(format) }
                if !cutoff.isEmpty { details.append(cutoff) }
                if !timeLimit.isEmpty { details.append(timeLimit) }

                return CompetitionScheduleEntry(
                    id: "\(title)-\(index)",
                    timeText: [start, end].filter { !$0.isEmpty }.joined(separator: "–"),
                    title: event,
                    detailText: details.isEmpty ? nil : details.joined(separator: " · ")
                )
            }

            guard !entries.isEmpty else { return nil }
            return CompetitionScheduleDay(
                id: "cubing-\(title)",
                title: title,
                entries: entries
            )
        }
    }

    nonisolated private static func cleanedCompetitionHTMLText(_ html: String) -> String {
        decodeCompetitionHTMLEntities(html)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"&nbsp;"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func normalizeCompetitionLookupKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/live/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/live/"#, with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? value
            .components(separatedBy: "?").first ?? value
            .components(separatedBy: "#").first ?? value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func strippingLocalizedOverrides(_ competition: CompetitionSummary) -> CompetitionSummary {
        CompetitionSummary(
            id: competition.id,
            name: competition.name,
            startDate: competition.startDate,
            endDate: competition.endDate,
            registrationOpen: competition.registrationOpen,
            registrationClose: competition.registrationClose,
            competitorLimit: competition.competitorLimit,
            venue: competition.venue,
            venueAddress: competition.venueAddress,
            venueDetails: competition.venueDetails,
            city: competition.city,
            countryISO2: competition.countryISO2,
            latitude: competition.latitude,
            longitude: competition.longitude,
            url: competition.url,
            website: competition.website,
            dateRange: competition.dateRange,
            eventIDs: competition.eventIDs,
            localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil,
            localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil
        )
    }

    private static func cacheKey(for query: CompetitionQuery) -> String {
        [
            query.languageCode,
            query.region.id,
            query.events.map(\.rawValue).sorted().joined(separator: ","),
            query.year.rawValue,
            query.status.rawValue
        ].joined(separator: "|")
    }

    private static func cacheKeyForTopCubers(competitionID: String) -> String {
        "top-cubers|v2|\(competitionID)"
    }
}

private actor CompetitionRecognizedCountryStore {
    static let shared = CompetitionRecognizedCountryStore()

    private var cachedCountries: [CompetitionRecognizedCountry]?
    private var hasLoadedFromDisk = false

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("competition-recognized-countries.json")
    }

    func recognizedCountries() async throws -> [CompetitionRecognizedCountry] {
        loadFromDiskIfNeeded()

        if let cachedCountries {
            return cachedCountries
        }

        let countries = try await CompetitionService.loadRecognizedCountriesFromWCA()
        cachedCountries = countries
        saveToDisk(countries)
        return countries
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard let data = try? Data(contentsOf: cacheFileURL()),
              let stored = try? JSONDecoder().decode([CompetitionRecognizedCountry].self, from: data),
              !stored.isEmpty else {
            return
        }

        cachedCountries = stored
    }

    private func saveToDisk(_ countries: [CompetitionRecognizedCountry]) {
        let cacheFileURL = cacheFileURL()
        guard !countries.isEmpty,
              let data = try? JSONEncoder().encode(countries) else { return }

        try? FileManager.default.createDirectory(
            at: cacheFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL, options: [.atomic])
    }
}

private actor CompetitionLocalizedNameStore {
    static let shared = CompetitionLocalizedNameStore()

    private var cachedLocalizedNames: [String: LocalizedCompetitionInfo]?
    private var hasLoadedFromDisk = false

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("competition-localized-names-v6.json")
    }

    func localizedCompetitionNames(
        loader: @escaping () async -> [String: LocalizedCompetitionInfo]
    ) async -> [String: LocalizedCompetitionInfo] {
        loadFromDiskIfNeeded()

        if let cachedLocalizedNames {
            return cachedLocalizedNames
        }

        let loaded = await loader()
        if !loaded.isEmpty {
            cachedLocalizedNames = loaded
            saveToDisk(loaded)
        }
        return loaded
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard let data = try? Data(contentsOf: cacheFileURL()),
              let stored = try? JSONDecoder().decode([String: LocalizedCompetitionInfo].self, from: data),
              !stored.isEmpty else {
            return
        }

        cachedLocalizedNames = stored
    }

    private func saveToDisk(_ localizedNames: [String: LocalizedCompetitionInfo]) {
        let cacheFileURL = cacheFileURL()
        guard !localizedNames.isEmpty,
              let data = try? JSONEncoder().encode(localizedNames) else { return }

        try? FileManager.default.createDirectory(
            at: cacheFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL, options: [.atomic])
    }
}

private actor CompetitionQueryCacheStore {
    static let shared = CompetitionQueryCacheStore()

    private var inMemorySnapshots: [String: CompetitionCacheSnapshot] = [:]
    private var hasLoadedFromDisk = false

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("competition-query-cache-v2.json")
    }

    func snapshot(for key: String) -> CompetitionCacheSnapshot? {
        loadFromDiskIfNeeded()
        return inMemorySnapshots[key]
    }

    func store(_ snapshot: CompetitionCacheSnapshot, for key: String) {
        loadFromDiskIfNeeded()
        inMemorySnapshots[key] = snapshot
        saveToDisk()
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard let data = try? Data(contentsOf: cacheFileURL()) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([String: StoredCompetitionCacheSnapshot].self, from: data) else {
            return
        }

        inMemorySnapshots = stored.mapValues { snapshot in
            CompetitionCacheSnapshot(
                competitions: snapshot.competitions,
                totalCount: snapshot.totalCount,
                lastUpdated: snapshot.lastUpdated
            )
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let stored = inMemorySnapshots.mapValues { snapshot in
            StoredCompetitionCacheSnapshot(
                competitions: snapshot.competitions,
                totalCount: snapshot.totalCount,
                lastUpdated: snapshot.lastUpdated
            )
        }

        let cacheFileURL = cacheFileURL()
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(
            at: cacheFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL, options: [.atomic])
    }
}

private actor CompetitionTopCuberStore {
    static let shared = CompetitionTopCuberStore()

    private var previewsByKey: [String: [CompetitionTopCuberPreview]] = [:]
    private var hasLoadedFromDisk = false

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("competition-top-cubers-cache-v1.json")
    }

    func previews(for key: String) -> [CompetitionTopCuberPreview]? {
        loadFromDiskIfNeeded()
        return previewsByKey[key]
    }

    func store(_ previews: [CompetitionTopCuberPreview], for key: String) {
        loadFromDiskIfNeeded()
        previewsByKey[key] = previews
        saveToDisk()
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard let data = try? Data(contentsOf: cacheFileURL()) else { return }
        let decoder = JSONDecoder()
        guard let stored = try? decoder.decode([String: [CompetitionTopCuberPreview]].self, from: data) else {
            return
        }
        previewsByKey = stored
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cacheFileURL = cacheFileURL()

        guard let data = try? encoder.encode(previewsByKey) else { return }

        try? FileManager.default.createDirectory(
            at: cacheFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheFileURL, options: [.atomic])
    }
}

private let competitionISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let competitionDateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let cubingCompetitionDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private let southAmericaCountryCodes: Set<String> = [
    "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PE", "PY", "SR", "UY", "VE"
]

private let northAmericaCountryCodes: Set<String> = [
    "AG", "AI", "AW", "BB", "BL", "BM", "BQ", "BS", "BZ", "CA", "CR", "CU", "CW", "DM",
    "DO", "GD", "GL", "GP", "GT", "HN", "HT", "JM", "KN", "KY", "LC", "MF", "MQ", "MS",
    "MX", "NI", "PA", "PM", "PR", "SV", "SX", "TC", "TT", "US", "VC", "VG", "VI"
]

private let europeCountryCodes: Set<String> = [
    "AD", "AL", "AT", "AX", "BA", "BE", "BG", "BY", "CH", "CY", "CZ", "DE", "DK", "EE",
    "ES", "FI", "FO", "FR", "GB", "GG", "GI", "GR", "HR", "HU", "IE", "IM", "IS", "IT",
    "JE", "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "MT", "NL", "NO", "PL", "PT",
    "RO", "RS", "RU", "SE", "SI", "SJ", "SK", "SM", "UA", "VA", "XK"
]

private let asiaCountryCodes: Set<String> = [
    "AE", "AF", "AM", "AZ", "BD", "BH", "BN", "BT", "CN", "GE", "HK", "ID", "IL", "IN",
    "IQ", "IR", "JO", "JP", "KG", "KH", "KP", "KR", "KW", "KZ", "LA", "LB", "LK", "MM",
    "MN", "MO", "MV", "MY", "NP", "OM", "PH", "PK", "PS", "QA", "SA", "SG", "SY", "TH",
    "TJ", "TM", "TR", "TW", "UZ", "VN", "YE"
]

private let africaCountryCodes: Set<String> = [
    "AO", "BF", "BI", "BJ", "BW", "CD", "CF", "CG", "CI", "CM", "CV", "DJ", "DZ", "EG",
    "EH", "ER", "ET", "GA", "GH", "GM", "GN", "GQ", "GW", "KE", "KM", "LR", "LS", "LY",
    "MA", "MG", "ML", "MR", "MU", "MW", "MZ", "NA", "NE", "NG", "RW", "SC", "SD", "SL",
    "SN", "SO", "SS", "ST", "SZ", "TD", "TG", "TN", "TZ", "UG", "ZA", "ZM", "ZW"
]

private let oceaniaCountryCodes: Set<String> = [
    "AS", "AU", "CK", "FJ", "FM", "GU", "KI", "MH", "MP", "NC", "NF", "NR", "NU", "NZ",
    "PF", "PG", "PN", "PW", "SB", "TK", "TO", "TV", "UM", "VU", "WF", "WS"
]

private struct LocalizedCompetitionInfo: Sendable, Codable {
    let slug: String?
    let name: String
    let regionPrimary: String?
    let regionSecondary: String?
    let address: String?
    let registrationStart: Date?
    let pauseRegistrationStart: Date?
    let reopenRegistration: Date?
    let registrationClose: Date?
}

private struct CubingCompetitionRegistrationInfo: Sendable {
    let registrationStart: Date?
    let pauseRegistrationStart: Date?
    let reopenRegistration: Date?
    let registrationClose: Date?
}

private func localizedCompetitionString(key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

private func localizedCountryName(for code: String, languageCode: String) -> String {
    appLocale(for: languageCode).localizedString(forRegionCode: code) ?? code
}

private func parseRecognizedCountryNames(from html: String) -> [String] {
    guard let listHTML = firstCountryMatch(
        in: html,
        pattern: #"(?s)<p>The WCA recognizes a total of .*?</p>\s*<ul>(.*?)</ul>"#
    ) else {
        return []
    }

    return countryMatches(in: listHTML, pattern: #"<li>\s*<strong>(.*?)</strong>"#)
        .map(decodeCompetitionHTMLEntities)
}

private func countryCode(forRecognizedCountryName name: String) -> String? {
    if let override = recognizedCountryCodeOverrides[name] {
        return override
    }

    let target = normalizedRecognizedCountryName(name)
    let englishLocale = Locale(identifier: "en_US")

    for code in Locale.isoRegionCodes {
        guard code.count == 2,
              let localized = englishLocale.localizedString(forRegionCode: code) else {
            continue
        }

        if normalizedRecognizedCountryName(localized) == target {
            return code
        }
    }

    return nil
}

private func normalizedRecognizedCountryName(_ name: String) -> String {
    var value = decodeCompetitionHTMLEntities(name)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))

    let substitutions: [(String, String)] = [
        ("&", "and"),
        ("macao", "macau"),
        ("cape verde", "cabo verde"),
        ("the gambia", "gambia"),
        ("czechia", "czech republic"),
        ("myanmar (burma)", "myanmar"),
        ("congo - brazzaville", "congo"),
        ("congo kinshasa", "democratic republic of the congo"),
        ("congo - kinshasa", "democratic republic of the congo"),
        ("hong kong sar china", "hong kong china"),
        ("macao sar china", "macau china"),
        ("palestinian territories", "palestine"),
        ("south korea", "republic of korea"),
        ("north korea", "democratic peoples republic of korea"),
        ("micronesia", "federated states of micronesia")
    ]

    for (source, target) in substitutions {
        value = value.replacingOccurrences(of: source, with: target)
    }

    return value
        .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
}

private func firstCountryMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let captureRange = Range(match.range(at: 1), in: text) else {
        return nil
    }

    return String(text[captureRange])
}

nonisolated private func firstCompetitionCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
        return nil
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else {
        return nil
    }

    return String(text[captureRange])
}

private func countryMatches(in text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return []
    }

    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, options: [], range: range).compactMap { match in
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}

nonisolated private func competitionHTMLCaptures(in text: String, pattern: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
        return []
    }

    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, options: [], range: range).map { match in
        (1 ..< match.numberOfRanges).compactMap { index -> String? in
            guard let captureRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }
}

nonisolated private func cubingPageRequiresLoginHTML(_ html: String) -> Bool {
    html.contains("site-login") || html.contains("<title>登录") || html.contains("<title>Login")
}

nonisolated private func cubingPageNotFoundHTML(_ html: String) -> Bool {
    html.localizedCaseInsensitiveContains("not found")
        || html.localizedCaseInsensitiveContains("页面不存在")
        || html.localizedCaseInsensitiveContains("404")
}

nonisolated private func competitionLooksLikePersonNameHTML(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard trimmed != "Name", trimmed != "姓名" else { return false }
    guard !trimmed.contains("/") else { return false }
    return trimmed.range(of: #"[A-Za-z\p{Script=Han}]"#, options: .regularExpression) != nil
}

nonisolated private func cubingCompetitorIdentifierHTML(number: String, nameCellHTML: String, name: String) -> String {
    if let href = firstCompetitionCapture(
        in: nameCellHTML,
        pattern: #"href=\"([^\"]+)\""#
    ) {
        return href
    }
    if !number.isEmpty {
        return "number-\(number)"
    }
    return "name-\(name)"
}

nonisolated private func extractCubingEventColumnIDsHTML(from html: String) -> [String] {
    let fallback = competitionSelectableEventIDs()
    let rowCaptures = competitionHTMLCaptures(
        in: html,
        pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#
    )

    for rowCapture in rowCaptures {
        guard let rowHTML = rowCapture.first else { continue }
        let matches = competitionHTMLCaptures(
            in: rowHTML,
            pattern: #"(?is)event-icon-([a-z0-9]+)"#
        )
        let eventIDs = matches.compactMap(\.first).filter { fallback.contains($0) }
        if eventIDs.count >= 2 {
            return eventIDs
        }
    }

    return fallback
}

nonisolated private func decodeCompetitionHTMLEntities(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

private let recognizedCountryCodeOverrides: [String: String] = [
    "Cabo Verde": "CV",
    "Congo": "CG",
    "Czech Republic": "CZ",
    "Democratic People's Republic of Korea": "KP",
    "Democratic Republic of the Congo": "CD",
    "Federated States of Micronesia": "FM",
    "Hong Kong, China": "HK",
    "Kosovo": "XK",
    "Macau, China": "MO",
    "North Macedonia": "MK",
    "Palestine": "PS",
    "Republic of Korea": "KR"
]

private struct WCACompetitionPayload: Decodable {
    let id: String
    let name: String
    let startDate: Date
    let endDate: Date
    let registrationOpen: Date?
    let registrationClose: Date?
    let competitorLimit: Int?
    let venue: String
    let venueAddress: String
    let venueDetails: String?
    let city: String
    let countryIso2: String
    let latitudeDegrees: Double?
    let longitudeDegrees: Double?
    let url: String
    let website: String?
    let dateRange: String
    let eventIds: [String]

    var summary: CompetitionSummary {
        CompetitionSummary(
            id: id,
            name: name,
            startDate: startDate,
            endDate: endDate,
            registrationOpen: registrationOpen,
            registrationClose: registrationClose,
            competitorLimit: competitorLimit,
            venue: venue,
            venueAddress: venueAddress,
            venueDetails: venueDetails,
            city: city,
            countryISO2: countryIso2,
            latitude: latitudeDegrees,
            longitude: longitudeDegrees,
            url: url,
            website: website,
            dateRange: dateRange,
            eventIDs: eventIds,
            localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil,
            localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil
        )
    }
}

private struct CompetitionPayloadPage: Sendable {
    let payloads: [WCACompetitionPayload]
    let totalCount: Int?
}

private struct StoredCompetitionCacheSnapshot: Codable {
    let competitions: [CompetitionSummary]
    let totalCount: Int?
    let lastUpdated: Date
}

private struct WCAScheduleProps: Decodable {
    let wcif: WCAWCIF
}

private struct WCAWCIF: Decodable {
    let schedule: WCASchedule
}

private struct WCASchedule: Decodable {
    let venues: [WCAVenue]
}

private struct WCAVenue: Decodable {
    let name: String
    let rooms: [WCARoom]
}

private struct WCARoom: Decodable {
    let name: String
    let activities: [WCAActivity]
}

private struct WCAActivity: Decodable {
    let id: Int
    let name: String
    let startTime: Date
    let endTime: Date
}
