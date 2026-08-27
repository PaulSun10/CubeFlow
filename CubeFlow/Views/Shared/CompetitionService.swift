import Foundation

struct CompetitionSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let shortDisplayName: String?
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
    let championshipTypes: [String]?
    var registrationStatus: WCACompetitionRegistrationStatus? = nil
    let localizedRegionLineOverride: String?
    let localizedAddressLineOverride: String?
    let localizedStatusOverride: CompetitionAvailabilityStatus?
    let localizedRegistrationStartOverride: Date?
    let localizedWaitlistStartOverride: Date?

    nonisolated var locationLine: String {
        if let localizedRegionLineOverride, !localizedRegionLineOverride.isEmpty {
            return localizedRegionLineOverride
        }
        return [city, localizedCountryName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    nonisolated var venueLine: String {
        parsedVenueLine.displayText
    }

    nonisolated var parsedVenueLine: CompetitionService.ParsedAddress {
        CompetitionService.parseAddress(rawVenueLine)
    }

    nonisolated var addressLinkSource: CompetitionService.ParsedAddress {
        let candidates = [rawVenueLine, localizedAddressLineOverride, venueAddress, venue, venueDetails]
            .compactMap { $0 }
            .map { CompetitionService.parseAddress($0) }
        return candidates.first(where: \.hasLinkedSegment) ?? parsedVenueLine
    }

    nonisolated var addressDestinationURL: URL? {
        [localizedAddressLineOverride, venueAddress, venue, venueDetails]
            .compactMap { $0 }
            .lazy
            .compactMap { CompetitionService.parseAddress($0).destinationURL }
            .first
    }

    nonisolated private var rawVenueLine: String {
        if let localizedAddressLineOverride, !localizedAddressLineOverride.isEmpty {
            return localizedAddressLineOverride
        }
        return [venue, venueDetails].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    nonisolated var localizedCountryName: String {
        Locale.current.localizedString(forRegionCode: countryISO2) ?? countryISO2
    }

    nonisolated var compactDisplayName: String {
        guard let shortDisplayName,
              !shortDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return name
        }
        return shortDisplayName
    }

    nonisolated var usesCubingChinaDetailSource: Bool {
        [website, url]
            .compactMap { $0 }
            .contains { value in
                guard let host = URL(string: value)?.host?.lowercased() else { return false }
                return host == "cubing.com"
                    || host == "www.cubing.com"
                    || host == "cubingchina.com"
                    || host == "www.cubingchina.com"
            }
    }

    nonisolated var cubingChinaCompetitionSlug: String? {
        for value in [website, url].compactMap({ $0 }) {
            guard let components = URLComponents(string: value),
                  let host = components.host?.lowercased(),
                  ["cubing.com", "www.cubing.com", "cubingchina.com", "www.cubingchina.com"].contains(host) else {
                continue
            }

            let pathComponents = components.path
                .split(separator: "/")
                .map(String.init)
            guard let competitionIndex = pathComponents.firstIndex(of: "competition"),
                  pathComponents.indices.contains(competitionIndex + 1) else {
                continue
            }

            let slug = pathComponents[competitionIndex + 1]
                .removingPercentEncoding?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !slug.isEmpty {
                return slug
            }
        }
        return nil
    }

    static func == (lhs: CompetitionSummary, rhs: CompetitionSummary) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum WCACompetitionRegistrationStatus: String, Hashable, Sendable, Codable {
    case notYetOpened = "not_yet_opened"
    case past
    case full
    case open
}

struct CompetitionRegistrationSummary: Hashable, Sendable, Codable {
    let acceptedCount: Int
    let waitlistedCount: Int

    var hasWaitlist: Bool { waitlistedCount > 0 }
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

    fileprivate var wcaAPIID: String {
        switch self {
        case .asia: return "_Asia"
        case .northAmerica: return "_North America"
        case .southAmerica: return "_South America"
        case .oceania: return "_Oceania"
        case .europe: return "_Europe"
        case .africa: return "_Africa"
        }
    }

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

    fileprivate nonisolated var countryCodes: Set<String> {
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
    case faceTurningOctahedron

    var id: String { rawValue }

    nonisolated static var selectableCases: [CompetitionEventFilter] {
        allCases.filter { $0 != .all }
    }

    nonisolated var wcaEventID: String {
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
        case .faceTurningOctahedron: return "fto"
        }
    }

    func localizedTitle(languageCode: String) -> String {
        if self != .all {
            return CompetitionEventPresentation.localizedFullName(
                for: wcaEventID,
                languageCode: languageCode
            )
        }

        let key: String
        switch self {
        case .all:
            key = "competitions.event.all"
        default:
            key = "competitions.event.all"
        }
        return localizedCompetitionString(key: key, languageCode: languageCode)
    }
}

enum CompetitionYearFilter: Hashable, Identifiable, Sendable {
    case all
    case year(Int)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .year(let year):
            return "year-\(year)"
        }
    }

    init(storedID: String) {
        if storedID == "all" {
            self = .all
        } else if storedID.hasPrefix("year-"),
                  let year = Int(storedID.dropFirst("year-".count)) {
            self = .year(year)
        } else {
            // Migrate the previous all/current/next persistence model.
            self = .all
        }
    }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .all:
            return localizedCompetitionString(key: "competitions.year.all", languageCode: languageCode)
        case .year(let year):
            return String(year)
        }
    }
}

enum CompetitionStatusFilter: String, CaseIterable, Identifiable {
    case present
    case recent
    case past

    var id: String { rawValue }

    static var selectableCases: [CompetitionStatusFilter] {
        [.present, .recent, .past]
    }

    func localizedTitle(languageCode: String) -> String {
        switch self {
        case .present:
            return localizedCompetitionString(key: "competitions.filter.status.present", languageCode: languageCode)
        case .recent:
            return localizedCompetitionString(key: "competitions.filter.status.recent", languageCode: languageCode)
        case .past:
            return localizedCompetitionString(key: "competitions.filter.status.past", languageCode: languageCode)
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
    let receivedCount: Int
    let nextPage: Int?
    let totalCount: Int?
}

nonisolated enum CompetitionListCountPresentation: Equatable, Sendable {
    case progress(loaded: Int, total: Int)
    case count(Int)
}

struct CompetitionDetailTextBlock: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String?
    let body: String
    let html: String?

    init(id: String, title: String?, body: String, html: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.html = html
    }
}

extension CompetitionService {
    nonisolated struct ParsedAddressSegment: Hashable, Sendable {
        let text: String
        let destinationURL: URL?
    }

    nonisolated struct ParsedAddress: Hashable, Sendable {
        let segments: [ParsedAddressSegment]
        let destinationURL: URL?

        var displayText: String {
            segments.map(\.text).joined()
        }

        var hasLinkedSegment: Bool {
            segments.contains(where: { $0.destinationURL != nil })
        }

        func projected(onto displayText: String) -> ParsedAddress {
            let links = segments.filter { $0.destinationURL != nil && !$0.text.isEmpty }
            guard !links.isEmpty else {
                return ParsedAddress(
                    segments: [ParsedAddressSegment(text: displayText, destinationURL: nil)],
                    destinationURL: nil
                )
            }

            var projected: [ParsedAddressSegment] = []
            var cursor = displayText.startIndex
            for link in links {
                guard let range = displayText.range(
                    of: link.text,
                    range: cursor ..< displayText.endIndex
                ) else {
                    continue
                }
                if cursor < range.lowerBound {
                    projected.append(ParsedAddressSegment(
                        text: String(displayText[cursor ..< range.lowerBound]),
                        destinationURL: nil
                    ))
                }
                projected.append(ParsedAddressSegment(
                    text: String(displayText[range]),
                    destinationURL: link.destinationURL
                ))
                cursor = range.upperBound
            }

            guard projected.contains(where: { $0.destinationURL != nil }) else {
                return ParsedAddress(
                    segments: [ParsedAddressSegment(text: displayText, destinationURL: nil)],
                    destinationURL: nil
                )
            }
            if cursor < displayText.endIndex {
                projected.append(ParsedAddressSegment(
                    text: String(displayText[cursor...]),
                    destinationURL: nil
                ))
            }
            return ParsedAddress(
                segments: projected,
                destinationURL: projected.lazy.compactMap(\.destinationURL).first
            )
        }
    }

    nonisolated static func inlineLinkSegments(in text: String) -> [(text: String, url: URL?)] {
        let pattern = #"\[([^\]\n]+)\]\s*\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [(text: text, url: nil)]
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else {
            return [(text: text, url: nil)]
        }

        var segments: [(text: String, url: URL?)] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                segments.append((
                    text: source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    url: nil
                ))
            }

            let label = source.substring(with: match.range(at: 1))
            let destination = source.substring(with: match.range(at: 2))
            if let url = URL(string: destination) {
                segments.append((text: label, url: url))
            } else {
                segments.append((text: source.substring(with: match.range), url: nil))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            segments.append((text: source.substring(from: cursor), url: nil))
        }
        return segments
    }

    nonisolated static func parseAddress(_ text: String) -> ParsedAddress {
        let inlineSegments = inlineLinkSegments(in: text)
        let markdownDestination = inlineSegments.lazy.compactMap(\.url).first
        let visibleText = inlineSegments.map(\.text).joined()
        let bareURLPattern = #"https?://[^\s)\]}]+"#
        let bareDestination: URL? = {
            guard markdownDestination == nil,
                  let regex = try? NSRegularExpression(pattern: bareURLPattern, options: .caseInsensitive) else {
                return nil
            }
            let source = visibleText as NSString
            guard let match = regex.firstMatch(
                in: visibleText,
                range: NSRange(location: 0, length: source.length)
            ) else {
                return nil
            }
            return URL(string: source.substring(with: match.range))
        }()

        var parsedSegments = inlineSegments.compactMap { segment -> ParsedAddressSegment? in
            let cleaned = segment.text
                .replacingOccurrences(
                    of: bareURLPattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                .replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t\r\f]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+\n"#, with: "\n", options: .regularExpression)
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return ParsedAddressSegment(text: cleaned, destinationURL: segment.url)
        }

        if let first = parsedSegments.first {
            parsedSegments[0] = ParsedAddressSegment(
                text: first.text.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression),
                destinationURL: first.destinationURL
            )
        }
        if let lastIndex = parsedSegments.indices.last {
            let last = parsedSegments[lastIndex]
            parsedSegments[lastIndex] = ParsedAddressSegment(
                text: last.text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression),
                destinationURL: last.destinationURL
            )
        }

        var mergedSegments: [ParsedAddressSegment] = []
        for segment in parsedSegments where !segment.text.isEmpty {
            if let last = mergedSegments.last,
               last.destinationURL == segment.destinationURL {
                mergedSegments[mergedSegments.count - 1] = ParsedAddressSegment(
                    text: last.text + segment.text,
                    destinationURL: last.destinationURL
                )
            } else {
                mergedSegments.append(segment)
            }
        }

        return ParsedAddress(
            segments: mergedSegments,
            destinationURL: markdownDestination ?? bareDestination
        )
    }

    nonisolated static func addressDisplayText(in text: String) -> String {
        parseAddress(text).displayText
    }
}

struct CompetitionScheduleEntry: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let timeText: String
    let title: String
    let detailText: String?
    let venueName: String?
    let roomID: String?
    let eventCode: String?
    let group: String?
    let round: String?
    let format: String?
    let cutoff: String?
    let timeLimit: String?
    let advancingCount: String?
    let startTime: Date?
    let endTime: Date?
    let roomColorHex: String?
    let startMinuteOfDay: Int?
    let endMinuteOfDay: Int?

    nonisolated init(
        id: String,
        timeText: String,
        title: String,
        detailText: String?,
        venueName: String?,
        roomID: String? = nil,
        eventCode: String?,
        group: String?,
        round: String?,
        format: String?,
        cutoff: String?,
        timeLimit: String?,
        advancingCount: String?,
        startTime: Date? = nil,
        endTime: Date? = nil,
        roomColorHex: String? = nil,
        startMinuteOfDay: Int? = nil,
        endMinuteOfDay: Int? = nil
    ) {
        self.id = id
        self.timeText = timeText
        self.title = title
        self.detailText = detailText
        self.venueName = venueName
        self.roomID = roomID
        self.eventCode = eventCode
        self.group = group
        self.round = round
        self.format = format
        self.cutoff = cutoff
        self.timeLimit = timeLimit
        self.advancingCount = advancingCount
        self.startTime = startTime
        self.endTime = endTime
        self.roomColorHex = roomColorHex
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }
}

struct CompetitionScheduleVenue: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let entries: [CompetitionScheduleEntry]
}

struct CompetitionScheduleDay: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let entries: [CompetitionScheduleEntry]
    let venues: [CompetitionScheduleVenue]
}

struct CompetitionScheduleRoomDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let colorHex: String?
}

enum CompetitionScheduleRoomFilter {
    nonisolated static func rooms(in days: [CompetitionScheduleDay]) -> [CompetitionScheduleRoomDescriptor] {
        var seen = Set<String>()
        var rooms: [CompetitionScheduleRoomDescriptor] = []

        // Venue rows retain the WCIF room order. Reading the globally time-sorted
        // day entries would make the selector order depend on the first activity.
        for day in days {
            for venue in day.venues {
                guard let entry = venue.entries.first,
                      let roomID = entry.roomID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !roomID.isEmpty,
                      seen.insert(roomID).inserted else {
                    continue
                }
                let roomName = venue.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !roomName.isEmpty else { continue }
                rooms.append(
                    CompetitionScheduleRoomDescriptor(
                        id: roomID,
                        name: roomName,
                        colorHex: entry.roomColorHex
                    )
                )
            }
        }
        return rooms
    }

    nonisolated static func filteredDays(
        _ days: [CompetitionScheduleDay],
        selectedRoomIDs: Set<String>
    ) -> [CompetitionScheduleDay] {
        days.map { day in
            let entries = day.entries.filter { entry in
                guard let roomID = entry.roomID else { return true }
                return selectedRoomIDs.contains(roomID)
            }
            let venues = day.venues.compactMap { venue -> CompetitionScheduleVenue? in
                let filteredEntries = venue.entries.filter { entry in
                    guard let roomID = entry.roomID else { return true }
                    return selectedRoomIDs.contains(roomID)
                }
                guard !filteredEntries.isEmpty else { return nil }
                return CompetitionScheduleVenue(
                    id: venue.id,
                    title: venue.title,
                    entries: filteredEntries
                )
            }
            return CompetitionScheduleDay(
                id: day.id,
                title: day.title,
                entries: entries,
                venues: venues
            )
        }
    }
}

struct CompetitionScheduleEventSummary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let eventCode: String?
    let title: String
    let detail: String
}

struct CompetitionWCAEventRound: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let formatID: String
    let timeLimitCentiseconds: Int?
    let cumulativeRoundIDs: [String]
    let cutoffAttempts: Int?
    let cutoffResult: Int?
    let advancementType: String?
    let advancementLevel: Int?
}

struct CompetitionWCAQualification: Hashable, Sendable, Codable {
    let whenDate: String
    let type: String
    let resultType: String
    let level: Int?
}

struct CompetitionWCAEvent: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let rounds: [CompetitionWCAEventRound]
    let qualification: CompetitionWCAQualification?
    let showsCutoffColumn: Bool
    let showsQualificationColumn: Bool
}

struct CompetitionScheduleDebugInfo: Hashable, Sendable, Codable {
    let source: String
    let slug: String?
    let htmlLength: Int
    let parseDurationMS: Int
    let hasOldStyleSection: Bool
    let htmlContainsTable: Bool
    let scheduleContainsTable: Bool
    let scheduleContainsResponsiveTable: Bool
    let panelCount: Int
    let tableCount: Int
    let entryCount: Int
    let panelPreview: String?
}

struct CompetitionTravelMapLocation: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let latitude: Double
    let longitude: Double
    let venue: String
    let address: String
}

struct CompetitionCompetitorPreview: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let number: String?
    let name: String
    let gender: String?
    let subtitle: String?
    let registeredEventIDs: [String]
    let wcaID: String?
    let countryISO2: String?

    nonisolated init(
        id: String,
        number: String?,
        name: String,
        gender: String?,
        subtitle: String?,
        registeredEventIDs: [String],
        wcaID: String? = nil,
        countryISO2: String? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.gender = gender
        self.subtitle = subtitle
        self.registeredEventIDs = registeredEventIDs
        self.wcaID = wcaID
        self.countryISO2 = countryISO2
    }
}

struct CompetitionPsychItem: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let rank: Int
    let resultText: String
    let singleWorldRank: Int?
    let singleResultText: String?
    let averageResultText: String?
    let averageWorldRank: Int?
    let tiedPrevious: Bool

    nonisolated init(
        id: String,
        eventID: String,
        rank: Int,
        resultText: String,
        singleWorldRank: Int? = nil,
        singleResultText: String? = nil,
        averageResultText: String? = nil,
        averageWorldRank: Int? = nil,
        tiedPrevious: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.rank = rank
        self.resultText = resultText
        self.singleWorldRank = singleWorldRank
        self.singleResultText = singleResultText
        self.averageResultText = averageResultText
        self.averageWorldRank = averageWorldRank
        self.tiedPrevious = tiedPrevious
    }
}

struct CompetitionCompetitorPsychPreview: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let wcaID: String?
    let items: [CompetitionPsychItem]
    let region: String?
    let countryISO2: String?

    nonisolated init(
        id: String,
        name: String,
        wcaID: String? = nil,
        items: [CompetitionPsychItem],
        region: String? = nil,
        countryISO2: String? = nil
    ) {
        self.id = id
        self.name = name
        self.wcaID = wcaID
        self.items = items
        self.region = region
        self.countryISO2 = countryISO2
    }
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

struct CompetitionLiveFilterOption: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let label: String
}

struct CompetitionLiveRoundOption: Identifiable, Hashable, Sendable, Codable {
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

struct CompetitionLiveStaticMessage: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let author: String
    let timestamp: Int
    let text: String
    let linkURL: URL?
}

struct CompetitionLiveSumOfRanksItem: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let eventID: String
    let rankText: String
}

struct CompetitionLiveSumOfRanksEntry: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let placeText: String
    let name: String
    let region: String
    let totalText: String
    let items: [CompetitionLiveSumOfRanksItem]
}

struct CompetitionLiveSumOfRanksContent: Hashable, Sendable, Codable {
    let eventIDs: [String]
    let entries: [CompetitionLiveSumOfRanksEntry]
}

struct CompetitionLivePodiumPlacement: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let placeText: String
    let name: String
    let bestText: String
    let averageText: String
    let region: String
}

struct CompetitionLivePodiumSection: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String?
    let placements: [CompetitionLivePodiumPlacement]
}

struct CompetitionLiveContent: Hashable, Sendable, Codable {
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

struct CompetitionWCALiveRound: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let eventID: String
    let eventName: String
    let roundName: String
    let number: Int?
    let formatID: String?
    let numberOfAttempts: Int?
    let sortBy: String?
    let isFinished: Bool?
    let advancementType: String?
    let advancementLevel: Int?
    let isActive: Bool
    let isOpen: Bool
    let results: [CompetitionWCALiveResultPreview]
}

struct CompetitionWCALiveResultPreview: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let ranking: Int?
    let personID: String?
    let name: String
    let region: String?
    let attempts: [Int]
    let best: Int
    let average: Int
    let isAdvancing: Bool?
    let isAdvancingQuestionable: Bool?
    let singleRecordTag: String?
    let averageRecordTag: String?
}

struct CompetitionWCALiveCompetitorResult: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let ranking: Int?
    let isAdvancing: Bool?
    let isAdvancingQuestionable: Bool?
    let attempts: [Int]
    let best: Int
    let average: Int
    let singleRecordTag: String?
    let averageRecordTag: String?
    let roundID: String
    let roundName: String
    let roundNumber: Int?
    let eventID: String
    let eventName: String
    let eventRank: Int?
    let formatID: String
    let numberOfAttempts: Int
    let sortBy: String
}

struct CompetitionWCALiveCompetitorContent: Hashable, Sendable, Codable {
    let id: String
    let name: String
    let wcaID: String?
    let countryISO2: String?
    let results: [CompetitionWCALiveCompetitorResult]
}

struct CompetitionWCALiveActivity: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let activityCode: String?
    let name: String
    let startTime: Date
    let endTime: Date
    let roomColorHex: String?
}

struct CompetitionWCALiveRecord: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let tag: String
    let type: String
    let attemptResult: Int
    let eventID: String
    let eventName: String
    let roundID: String
    let personName: String
    let countryName: String
}

struct CompetitionWCALiveRoom: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let currentActivityName: String?
    let currentActivityStart: Date?
    let currentActivityEnd: Date?
    let nextActivityName: String?
    let nextActivityStart: Date?
    let activities: [CompetitionWCALiveActivity]?
}

struct CompetitionWCALiveVenue: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let countryName: String?
    let rooms: [CompetitionWCALiveRoom]
}

struct CompetitionWCALiveContent: Hashable, Sendable, Codable {
    let competitionID: Int
    let competitionName: String?
    let eventIDs: [String]
    let rounds: [CompetitionWCALiveRound]
    let venues: [CompetitionWCALiveVenue]
    let records: [CompetitionWCALiveRecord]?
}

enum CompetitionLiveAvailability: String, Hashable, Sendable, Codable {
    case loading
    case available
    case unavailable
    case failed
    case upcoming
    case ended
}

nonisolated enum CompetitionWCALiveLookupState: Hashable, Sendable {
    case loading
    case available(competitionID: Int, url: URL)
    case unavailable
    case failed

    var availableURL: URL? {
        guard case let .available(_, url) = self else { return nil }
        return url
    }
}

struct CompetitionDetailContent: Hashable, Sendable, Codable {
    let overviewBlocks: [CompetitionDetailTextBlock]
    let noteBlocks: [CompetitionDetailTextBlock]
    let regulationBlocks: [CompetitionDetailTextBlock]
    let travelBlocks: [CompetitionDetailTextBlock]
    let travelMapLocations: [CompetitionTravelMapLocation]
    let registerBlocks: [CompetitionDetailTextBlock]
    let scheduleDays: [CompetitionScheduleDay]
    let scheduleEventSummaries: [CompetitionScheduleEventSummary]
    let wcaEvents: [CompetitionWCAEvent]
    let scheduleIntroHTML: String?
    let scheduleCommentHTML: String?
    let scheduleDebugInfo: CompetitionScheduleDebugInfo?
    let localizedName: String?
    let championshipTitles: [String]?
    let competitorsCount: Int?
    let competitorPreviews: [CompetitionCompetitorPreview]
    let registrationRequiresSignIn: Bool
    let hasRegisterLink: Bool
    let hasCompetitorsLink: Bool
    let liveAvailability: CompetitionLiveAvailability
    let liveURLOverride: URL?
    let liveContent: CompetitionLiveContent?
    let wcaLiveContent: CompetitionWCALiveContent?

    nonisolated static let empty = CompetitionDetailContent(
        overviewBlocks: [],
        noteBlocks: [],
        regulationBlocks: [],
        travelBlocks: [],
        travelMapLocations: [],
        registerBlocks: [],
        scheduleDays: [],
        scheduleEventSummaries: [],
        wcaEvents: [],
        scheduleIntroHTML: nil,
        scheduleCommentHTML: nil,
        scheduleDebugInfo: nil,
        localizedName: nil,
        championshipTitles: nil,
        competitorsCount: nil,
        competitorPreviews: [],
        registrationRequiresSignIn: false,
        hasRegisterLink: false,
        hasCompetitorsLink: false,
        liveAvailability: .loading,
        liveURLOverride: nil,
        liveContent: nil,
        wcaLiveContent: nil
    )

    func replacingCompetitors(from other: CompetitionDetailContent) -> CompetitionDetailContent {
        CompetitionDetailContent(
            overviewBlocks: overviewBlocks,
            noteBlocks: noteBlocks,
            regulationBlocks: regulationBlocks,
            travelBlocks: travelBlocks,
            travelMapLocations: travelMapLocations,
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            scheduleEventSummaries: scheduleEventSummaries,
            wcaEvents: wcaEvents,
            scheduleIntroHTML: scheduleIntroHTML,
            scheduleCommentHTML: scheduleCommentHTML,
            scheduleDebugInfo: scheduleDebugInfo,
            localizedName: localizedName,
            championshipTitles: championshipTitles,
            competitorsCount: other.competitorsCount,
            competitorPreviews: other.competitorPreviews,
            registrationRequiresSignIn: registrationRequiresSignIn,
            hasRegisterLink: hasRegisterLink,
            hasCompetitorsLink: hasCompetitorsLink,
            liveAvailability: liveAvailability,
            liveURLOverride: liveURLOverride,
            liveContent: liveContent,
            wcaLiveContent: wcaLiveContent
        )
    }

    func replacingLive(from other: CompetitionDetailContent) -> CompetitionDetailContent {
        CompetitionDetailContent(
            overviewBlocks: overviewBlocks,
            noteBlocks: noteBlocks,
            regulationBlocks: regulationBlocks,
            travelBlocks: travelBlocks,
            travelMapLocations: travelMapLocations,
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            scheduleEventSummaries: scheduleEventSummaries,
            wcaEvents: wcaEvents,
            scheduleIntroHTML: scheduleIntroHTML,
            scheduleCommentHTML: scheduleCommentHTML,
            scheduleDebugInfo: scheduleDebugInfo,
            localizedName: localizedName,
            championshipTitles: championshipTitles,
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: registrationRequiresSignIn,
            hasRegisterLink: other.hasRegisterLink || hasRegisterLink,
            hasCompetitorsLink: other.hasCompetitorsLink || hasCompetitorsLink,
            liveAvailability: other.liveAvailability,
            liveURLOverride: other.liveURLOverride,
            liveContent: other.liveContent,
            wcaLiveContent: other.wcaLiveContent
        )
    }

    func replacingWCALiveAvailability(
        _ availability: CompetitionLiveAvailability,
        url: URL?
    ) -> CompetitionDetailContent {
        CompetitionDetailContent(
            overviewBlocks: overviewBlocks,
            noteBlocks: noteBlocks,
            regulationBlocks: regulationBlocks,
            travelBlocks: travelBlocks,
            travelMapLocations: travelMapLocations,
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            scheduleEventSummaries: scheduleEventSummaries,
            wcaEvents: wcaEvents,
            scheduleIntroHTML: scheduleIntroHTML,
            scheduleCommentHTML: scheduleCommentHTML,
            scheduleDebugInfo: scheduleDebugInfo,
            localizedName: localizedName,
            championshipTitles: championshipTitles,
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: registrationRequiresSignIn,
            hasRegisterLink: hasRegisterLink,
            hasCompetitorsLink: hasCompetitorsLink,
            liveAvailability: availability,
            liveURLOverride: url,
            liveContent: liveContent,
            wcaLiveContent: wcaLiveContent
        )
    }
}

nonisolated private func competitionSelectableEventIDs() -> [String] {
    [
        "222", "333", "444", "555", "666", "777",
        "333bf", "333fm", "333oh", "clock", "minx", "pyram",
        "skewb", "sq1", "444bf", "555bf", "333mbf", "fto"
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
    case rateLimited(retryAfter: TimeInterval)

    var rateLimitRetryDelay: TimeInterval? {
        guard case .rateLimited(let retryAfter) = self else { return nil }
        return retryAfter
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return currentAppLocalizedString("competitions.error_invalid_url")
        case .requestFailed:
            return currentAppLocalizedString("competitions.error_request_failed")
        case .rateLimited:
            return currentAppLocalizedString(
                "competitions.rate_limited",
                defaultValue: "WCA request limit reached. Loading will resume shortly."
            )
        }
    }
}

enum CompetitionService {
    nonisolated static let recentCompetitionLookbackDays = 30
    nonisolated static let competitionPageSize = 500

    nonisolated static func listCountPresentation(
        loadedCount: Int,
        visibleCount: Int,
        totalCount: Int?,
        hasPendingPages: Bool
    ) -> CompetitionListCountPresentation {
        let loaded = max(loadedCount, visibleCount)
        if let totalCount, hasPendingPages, loaded < totalCount {
            return .progress(loaded: loaded, total: totalCount)
        }
        return .count(hasPendingPages ? loaded : visibleCount)
    }

    private static func isTimeoutLikeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return true
        }
        return nsError.localizedDescription.lowercased().contains("timed out")
    }

    static func warmRecognizedCountriesCache() async {
        _ = try? await CompetitionRecognizedCountryStore.shared.recognizedCountries()
    }

    static func clearCompetitionListCache() async {
        await CompetitionQueryCacheStore.shared.clear()
        await CompetitionInFlightRequestStore.shared.clear()
    }

    static func clearCompetitionSupportCache() async {
        await CompetitionLocalizedNameStore.shared.clear()
        await CompetitionRecognizedCountryStore.shared.clear()
    }

    static func clearCompetitionDetailCache() async {
        await CompetitionDetailContentStore.shared.clear()
        await CompetitionWCALiveLookupStore.shared.clear()
        await CompetitionScheduleParseStore.shared.clear()
        await CompetitionRegistrationSummaryStore.shared.clear()
        await CompetitionInFlightRequestStore.shared.clear()
    }

    static func clearCompetitionTopCubersCache() async {
        await CompetitionTopCuberStore.shared.clear()
        await CompetitionInFlightRequestStore.shared.clear()
    }

    static func clearAllCompetitionCaches() async {
        await clearCompetitionListCache()
        await clearCompetitionSupportCache()
        await clearCompetitionDetailCache()
        await clearCompetitionTopCubersCache()
    }

    static func fetchCompetitionDetail(
        for competition: CompetitionSummary,
        languageCode: String,
        forceRefresh: Bool = false,
        includeCompetitors: Bool = false,
        includeLive: Bool = false
    ) async -> CompetitionDetailContent {
        let key = cacheKeyForDetail(
            competitionID: competition.id,
            languageCode: languageCode,
            includeCompetitors: includeCompetitors,
            includeLive: includeLive
        )
        if !forceRefresh,
           let cached = await CompetitionDetailContentStore.shared.content(for: key) {
            return cached
        }

        let requestKey = forceRefresh ? "\(key)|force" : key
        let content = await CompetitionInFlightRequestStore.shared.detailContent(for: requestKey) {
            if competition.usesCubingChinaDetailSource {
                return await fetchCubingCompetitionDetail(
                    for: competition,
                    languageCode: languageCode,
                    forceRefresh: forceRefresh,
                    includeCompetitors: includeCompetitors,
                    includeLive: includeLive
                ) ?? .empty
            }

            return await fetchWCACompetitionDetail(
                for: competition,
                languageCode: languageCode,
                forceRefresh: forceRefresh,
                includeCompetitors: includeCompetitors,
                includeLive: includeLive
            ) ?? .empty
        }

        if content != .empty {
            await CompetitionDetailContentStore.shared.store(content, for: key)
        }
        return content
    }

    static func fetchCompetitionPsychPreviews(
        for competition: CompetitionSummary,
        languageCode: String,
        eventID: String?,
        sortBy: String? = nil
    ) async -> [CompetitionCompetitorPsychPreview] {
        let trimmedEventID = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetEventID = trimmedEventID.isEmpty ? nil : trimmedEventID

        if competition.usesCubingChinaDetailSource {
            return await fetchCubingPsychPreviews(
                for: competition,
                languageCode: languageCode,
                eventID: targetEventID
            )
        }

        return await fetchWCAPsychPreviews(
            for: competition,
            languageCode: languageCode,
            eventID: targetEventID,
            sortBy: sortBy
        )
    }


    static func fetchCompetitionRegistrationSummary(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionRegistrationSummary? {
        guard !competition.usesCubingChinaDetailSource else { return nil }
        let key = competition.id
        if let cached = await CompetitionRegistrationSummaryStore.shared.summary(for: key) {
            return cached
        }

        guard let fetched = await CompetitionInFlightRequestStore.shared.registrationSummary(for: key, loader: {
            await fetchWCARegistrationSummary(for: competition, languageCode: languageCode)
        }) else {
            return nil
        }
        await CompetitionRegistrationSummaryStore.shared.store(fetched, for: key)
        return fetched
    }

    private static func fetchWCARegistrationSummary(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> CompetitionRegistrationSummary? {
        guard let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(competition.id)/wcif/public") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
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

        var acceptedCount = 0
        var waitlistedCount = 0
        for person in wcif.persons {
            guard let registration = person.registration else { continue }
            let status = registration.status?.lowercased() ?? ""
            if registration.isCompeting == true || status == "accepted" {
                acceptedCount += 1
            } else if status == "waiting_list" || status == "waitlisted" || status == "waiting-list" {
                waitlistedCount += 1
            }
        }

        return CompetitionRegistrationSummary(
            acceptedCount: acceptedCount,
            waitlistedCount: waitlistedCount
        )
    }

    static func fetchCompetitionTopCuberPreviews(
        for competition: CompetitionSummary,
        languageCode: String
    ) async -> [CompetitionTopCuberPreview]? {
        let key = cacheKeyForTopCubers(competitionID: competition.id)
        if let cached = await CompetitionTopCuberStore.shared.previews(for: key) {
            return cached
        }

        guard let fetched = await CompetitionInFlightRequestStore.shared.topCuberPreviews(for: key, loader: {
            await fetchWCATopCuberPreviews(for: competition, languageCode: languageCode)
        }) else {
            return nil
        }
        await CompetitionTopCuberStore.shared.store(
            fetched,
            for: key
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
        guard !competition.usesCubingChinaDetailSource else { return nil }
        return await fetchWCALiveContent(for: competition, languageCode: languageCode, liveURL: nil)
    }

    static func fetchCompetitionWCALiveAvailability(
        for competition: CompetitionSummary,
        languageCode: String,
        hintedURL: URL?,
        forceRefresh: Bool = false
    ) async -> CompetitionWCALiveLookupState {
        guard !competition.usesCubingChinaDetailSource else { return .unavailable }
        return await lookupWCALiveCompetition(
            for: competition,
            languageCode: languageCode,
            hintedURL: hintedURL,
            forceRefresh: forceRefresh
        )
    }

    static func fetchCompetitionWCALiveRoundSnapshot(
        round: CompetitionWCALiveRound,
        languageCode: String
    ) async -> CompetitionWCALiveRound? {
        await fetchWCALiveRoundSnapshot(
            roundID: round.id,
            languageCode: languageCode,
            fallback: round
        )
    }

    nonisolated static func decodeWCALiveRoundSubscriptionResult(
        _ data: Data,
        fallback: CompetitionWCALiveRound
    ) -> CompetitionWCALiveRound? {
        guard let graph = try? JSONDecoder().decode(WCALiveRoundUpdateGraphQLResponse.self, from: data),
              let round = graph.data?.roundUpdated,
              round.id == fallback.id else {
            return nil
        }
        return competitionWCALiveRound(from: round, fallback: fallback)
    }

    nonisolated static func wcaLiveProbeContainsCompetition(_ data: Data) -> Bool {
        guard let response = try? JSONDecoder().decode(WCALiveProbeGraphQLResponse.self, from: data),
              let competition = response.data?.competition else {
            return false
        }
        return !competition.id.isEmpty && !competition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func wcaLiveProbeMatchesCompetition(
        _ data: Data,
        wcaCompetitionID: String
    ) -> Bool {
        guard let response = try? JSONDecoder().decode(WCALiveProbeGraphQLResponse.self, from: data),
              let competition = response.data?.competition else {
            return false
        }
        return !competition.id.isEmpty
            && !competition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && competition.wcaId == wcaCompetitionID
    }

    static func fetchWCALiveCompetitorContent(
        personID: String,
        languageCode: String
    ) async -> CompetitionWCALiveCompetitorContent? {
        await fetchWCALiveCompetitor(personID: personID, languageCode: languageCode)
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

        let competitions = await Task.detached(priority: .utility) {
            snapshot.competitions.map(strippingLocalizedOverrides)
        }.value

        return CompetitionCacheSnapshot(
            competitions: competitions,
            totalCount: snapshot.totalCount,
            lastUpdated: snapshot.lastUpdated
        )
    }

    nonisolated static func filterCompetitions(
        _ competitions: [CompetitionSummary],
        for query: CompetitionQuery,
        now: Date = Date()
    ) -> [CompetitionSummary] {
        competitions
            .filter { matchesRegion($0, region: query.region) }
            .filter { matchesEvents($0, selectedEvents: query.events) }
            .filter { matchesStatus($0, status: query.status, now: now) }
            .filter { matchesYear($0, year: query.year, status: query.status) }
            .sorted { lhs, rhs in
                if query.status == .present {
                    if lhs.startDate != rhs.startDate {
                        return lhs.startDate < rhs.startDate
                    }
                    if lhs.endDate != rhs.endDate {
                        return lhs.endDate < rhs.endDate
                    }
                } else {
                    let lhsYear = officialCompetitionYear(for: lhs)
                    let rhsYear = officialCompetitionYear(for: rhs)
                    if lhsYear != rhsYear {
                        return lhsYear > rhsYear
                    }
                    if lhs.endDate != rhs.endDate {
                        return lhs.endDate > rhs.endDate
                    }
                    if lhs.startDate != rhs.startDate {
                        return lhs.startDate > rhs.startDate
                    }
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
        let normalizedCompetitions = await Task.detached(priority: .utility) {
            filterCompetitions(competitions, for: query).map(strippingLocalizedOverrides)
        }.value
        let snapshot = CompetitionCacheSnapshot(
            competitions: normalizedCompetitions,
            totalCount: totalCount,
            lastUpdated: Date()
        )
        await CompetitionQueryCacheStore.shared.store(snapshot, for: cacheKey(for: query))
    }

    static func fetchCompetitionsPage(query: CompetitionQuery, page: Int) async throws -> CompetitionPageResult {
        let key = "\(cacheKey(for: query))|page:\(page)"
        return try await CompetitionInFlightRequestStore.shared.competitionsPage(for: key) {
            try await fetchCompetitionsPageUncoordinated(query: query, page: page)
        }
    }

    private static func fetchCompetitionsPageUncoordinated(query: CompetitionQuery, page: Int) async throws -> CompetitionPageResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recentWindowStart = calendar.date(
            byAdding: .day,
            value: -recentCompetitionLookbackDays,
            to: today
        ) ?? today
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "per_page", value: String(competitionPageSize)))

        switch query.status {
        case .present:
            queryItems.append(URLQueryItem(name: "ongoing_and_future", value: apiDateString(from: today)))
            queryItems.append(URLQueryItem(name: "sort", value: "start_date,end_date,name"))
        case .recent:
            queryItems.append(URLQueryItem(name: "start", value: apiDateString(from: recentWindowStart)))
            queryItems.append(URLQueryItem(name: "end", value: apiDateString(from: today)))
            queryItems.append(URLQueryItem(name: "sort", value: "-end_date,-start_date,name"))
        case .past:
            queryItems.append(URLQueryItem(name: "end", value: apiDateString(from: today)))
            queryItems.append(URLQueryItem(name: "sort", value: "-end_date,-start_date,name"))
        }

        if query.status == .past, case .year(let year) = query.year,
           let range = yearRange(for: year, endingNoLaterThan: today) {
            queryItems = replacingDateBounds(existing: queryItems, with: range)
        }

        let allSelectableEvents = Set(CompetitionEventFilter.selectableCases)
        if !query.events.isEmpty, query.events != allSelectableEvents {
            for event in query.events.sorted(by: { $0.rawValue < $1.rawValue }) {
                queryItems.append(URLQueryItem(name: "event_ids[]", value: event.wcaEventID))
            }
        }

        switch query.region {
        case .all:
            break
        case .continent(let continent):
            queryItems.append(URLQueryItem(name: "continent", value: continent.wcaAPIID))
        case .country(let code):
            queryItems.append(URLQueryItem(name: "country_iso2", value: code))
        }

        let payloadPage = try await fetchCompetitionPayloadPage(
            queryItems: queryItems,
            page: page,
            languageCode: query.languageCode
        )

        var baseCompetitions = payloadPage.payloads
            .map(\.summary)
            .filter { matchesRegion($0, region: query.region) }
            .filter { matchesEvents($0, selectedEvents: query.events) }
        // Ended competitions never need live registration state. Avoiding this
        // second request per page keeps a complete Past traversal below WCA's
        // production API rate limit.
        let registrationStatuses = query.status == .present
            ? await fetchRegistrationStatuses(
                competitionIDs: baseCompetitions.map(\.id),
                languageCode: query.languageCode
            )
            : [:]
        for index in baseCompetitions.indices {
            baseCompetitions[index].registrationStatus = registrationStatuses[baseCompetitions[index].id]
        }
        let localizedCompetitions = await localizeCompetitionNamesIfNeeded(
            baseCompetitions,
            languageCode: query.languageCode
        )
        let competitions = filterCompetitions(localizedCompetitions, for: query)

        return CompetitionPageResult(
            competitions: competitions,
            receivedCount: payloadPage.payloads.count,
            nextPage: nextCompetitionPage(
                currentPage: page,
                receivedCount: payloadPage.payloads.count,
                totalCount: payloadPage.totalCount,
                pageSize: payloadPage.pageSize
            ),
            totalCount: payloadPage.totalCount
        )
    }

    static func nextCompetitionPage(
        currentPage: Int,
        receivedCount: Int,
        totalCount: Int?,
        pageSize: Int = 25
    ) -> Int? {
        guard receivedCount > 0 else { return nil }
        if let totalCount {
            return currentPage * pageSize < totalCount ? currentPage + 1 : nil
        }
        return receivedCount < pageSize ? nil : currentPage + 1
    }

    nonisolated static func officialCompetitionYear(for competition: CompetitionSummary) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Match WCA's CompetitionOverview `startYear` helper, which groups the
        // production list by the UTC year of `end_date` despite its name.
        return calendar.component(.year, from: competition.endDate)
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

            let usesCubingChinaOverrides = competition.usesCubingChinaDetailSource
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
                shortDisplayName: localizedName == competition.name ? competition.shortDisplayName : localizedName,
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
                championshipTypes: competition.championshipTypes,
                registrationStatus: competition.registrationStatus,
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

    nonisolated private static func matchesRegion(_ competition: CompetitionSummary, region: CompetitionRegionFilter) -> Bool {
        switch region {
        case .all:
            return true
        case .country(let code):
            return competition.countryISO2 == code
        case .continent(let continent):
            return continent.countryCodes.contains(competition.countryISO2)
        }
    }

    nonisolated private static func matchesEvents(_ competition: CompetitionSummary, selectedEvents: Set<CompetitionEventFilter>) -> Bool {
        let allSelectableEvents = Set(CompetitionEventFilter.selectableCases)
        if selectedEvents.isEmpty || selectedEvents == allSelectableEvents {
            return true
        }

        let selectedEventIDs = selectedEvents.map(\.wcaEventID)
        return selectedEventIDs.allSatisfy { competition.eventIDs.contains($0) }
    }

    nonisolated private static func matchesStatus(_ competition: CompetitionSummary, status: CompetitionStatusFilter, now: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: competition.startDate)
        let endDay = calendar.startOfDay(for: competition.endDate)
        let recentStart = calendar.date(
            byAdding: .day,
            value: -recentCompetitionLookbackDays,
            to: today
        ) ?? today

        switch status {
        case .present:
            return endDay >= today
        case .recent:
            return startDay >= recentStart && endDay <= today
        case .past:
            return endDay <= today
        }
    }

    nonisolated private static func matchesYear(
        _ competition: CompetitionSummary,
        year: CompetitionYearFilter,
        status: CompetitionStatusFilter
    ) -> Bool {
        guard status == .past else { return true }
        guard case .year(let selectedYear) = year else { return true }
        return officialCompetitionYear(for: competition) == selectedYear
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

        switch competition.registrationStatus {
        case .notYetOpened:
            return .registrationNotOpenYet
        case .full:
            return .waitlist
        case .open:
            return .registrationOpen
        case .past, .none:
            break
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
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func yearRange(for year: Int, endingNoLaterThan today: Date) -> (start: String, end: String)? {
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return nil
        }
        let end = min(yearEnd, today)
        guard start <= end else { return nil }
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
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(acceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")

        let (data, httpResponse) = try await fetchCompetitionPageData(request: request)

        let payloads = try await Task.detached(priority: .utility) {
            try decodeCompetitionPayloads(data)
        }.value
        let totalCount = httpResponse.value(forHTTPHeaderField: "total").flatMap(Int.init)
        let responsePageSize = httpResponse.value(forHTTPHeaderField: "per-page").flatMap(Int.init)
            ?? competitionPageSize
        return CompetitionPayloadPage(
            payloads: payloads,
            totalCount: totalCount,
            pageSize: responsePageSize
        )
    }

    private static func fetchCompetitionPageData(
        request: URLRequest,
        maximumAttempts: Int = 5
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CompetitionServiceError.requestFailed
                }
                if 200 ..< 300 ~= httpResponse.statusCode {
                    return (data, httpResponse)
                }

                let isRateLimited = httpResponse.statusCode == 429
                if isRateLimited {
                    throw CompetitionServiceError.rateLimited(
                        retryAfter: rateLimitRetryDelay(from: httpResponse)
                    )
                }
                let isRetryable = (500 ... 599).contains(httpResponse.statusCode)
                guard isRetryable, attempt + 1 < maximumAttempts else {
                    throw CompetitionServiceError.requestFailed
                }
                let delay = min(pow(2, Double(attempt)), 8)
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                guard isTimeoutLikeError(error), attempt + 1 < maximumAttempts else { throw error }
                let delay = min(0.35 * pow(2, Double(attempt)), 4)
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func rateLimitRetryDelay(from response: HTTPURLResponse) -> TimeInterval {
        if let rawRetryAfter = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(rawRetryAfter) {
                return max(seconds, 1)
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            if let retryDate = formatter.date(from: rawRetryAfter) {
                return max(retryDate.timeIntervalSinceNow, 1)
            }
        }

        for header in ["RateLimit-Reset", "X-RateLimit-Reset"] {
            guard let rawReset = response.value(forHTTPHeaderField: header),
                  let reset = TimeInterval(rawReset) else { continue }
            let delay = reset > Date().timeIntervalSince1970
                ? reset - Date().timeIntervalSince1970
                : reset
            return max(delay, 1)
        }
        return 60
    }

    nonisolated private static func decodeCompetitionPayloads(_ data: Data) throws -> [WCACompetitionPayload] {
        let dateParser = CompetitionPayloadDateParser()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = dateParser.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported competition date format: \(value)"
            )
        }
        return try decoder.decode([WCACompetitionPayload].self, from: data)
    }

    private static func fetchRegistrationStatuses(
        competitionIDs: [String],
        languageCode: String
    ) async -> [String: WCACompetitionRegistrationStatus] {
        guard !competitionIDs.isEmpty,
              let url = URL(string: "https://www.worldcubeassociation.org/api/v0/registration-data") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(acceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": competitionIDs])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let payloads = try? JSONDecoder().decode([WCARegistrationStatusPayload].self, from: data) else {
            return [:]
        }

        return payloads.reduce(into: [:]) { statuses, payload in
            statuses[payload.id] = payload.registrationStatus
        }
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
        languageCode: String,
        forceRefresh: Bool,
        includeCompetitors: Bool,
        includeLive: Bool
    ) async -> CompetitionDetailContent? {
        guard let url = URL(string: competition.url) else { return nil }
        guard let html = await fetchCompetitionHTML(url: url, languageCode: languageCode) else { return nil }

        async let registerBlocksTask = fetchWCARegisterBlocks(for: competition, languageCode: languageCode)
        let extractedLiveURL = extractWCALiveURL(from: html)
        async let liveLookupTask = lookupWCALiveCompetition(
            for: competition,
            languageCode: languageCode,
            hintedURL: extractedLiveURL,
            forceRefresh: forceRefresh
        )

        let noteBlocks = extractWCATabBlocks(from: html, languageCode: languageCode)
        let wcaEvents = extractWCAEvents(from: html)
        let scheduleDays = await CompetitionScheduleParseStore.shared.scheduleDays(
            for: "wca|rooms-v2|\(languageCode)|\(competition.id)",
            forceRefresh: forceRefresh
        ) {
            await decodeWCAScheduleDays(from: html, languageCode: languageCode)
        }
        let competitorsHTML = includeCompetitors
            ? await fetchCompetitionHTML(
                url: URL(string: competition.url + "/registrations"),
                languageCode: languageCode
            )
            : nil
        let publicWCIFCompetitors = includeCompetitors
            ? await fetchWCAPublicCompetitors(for: competition, languageCode: languageCode)
            : WCAPublicCompetitors(previews: [], count: nil)
        let competitorPreviews = includeCompetitors
            ? (publicWCIFCompetitors.previews.isEmpty
                ? extractWCACompetitorPreviews(from: competitorsHTML)
                : publicWCIFCompetitors.previews)
            : []
        let competitorsCount = includeCompetitors
            ? (publicWCIFCompetitors.count
                ?? extractWCACompetitorCount(from: html)
                ?? extractWCACompetitorCount(from: competitorsHTML))
            : extractWCACompetitorCount(from: html)
        let registerBlocks = await registerBlocksTask
        let hasRegisterLink = hasWCARegisterLink(from: html, competitionID: competition.id)
        let hasCompetitorsLink = hasWCACompetitorsLink(from: html, competitionID: competition.id)
        let liveLookup = await liveLookupTask
        let liveURLOverride = liveLookup.availableURL
        let wcaLiveContent = includeLive && liveURLOverride != nil
            ? await fetchWCALiveContent(
                for: competition,
                languageCode: languageCode,
                liveURL: liveURLOverride
            )
            : nil
        let liveAvailability = wcaLiveAvailability(for: liveLookup)

        return CompetitionDetailContent(
            overviewBlocks: [],
            noteBlocks: noteBlocks,
            regulationBlocks: [],
            travelBlocks: [],
            travelMapLocations: [],
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            scheduleEventSummaries: [],
            wcaEvents: wcaEvents,
            scheduleIntroHTML: nil,
            scheduleCommentHTML: nil,
            scheduleDebugInfo: nil,
            localizedName: nil,
            championshipTitles: extractWCAChampionshipTitles(from: html),
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: false,
            hasRegisterLink: hasRegisterLink,
            hasCompetitorsLink: hasCompetitorsLink,
            liveAvailability: liveAvailability,
            liveURLOverride: liveURLOverride,
            liveContent: nil,
            wcaLiveContent: wcaLiveContent
        )
    }

    private static func fetchCubingCompetitionDetail(
        for competition: CompetitionSummary,
        languageCode: String,
        forceRefresh: Bool,
        includeCompetitors: Bool,
        includeLive: Bool
    ) async -> CompetitionDetailContent? {
        guard let slug = competitionSlug(for: competition) else { return nil }
        let cubingLanguage = cubingLanguageCode(for: languageCode)

        async let mainHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)?lang=\(cubingLanguage)"),
            languageCode: languageCode
        )
        async let regulationsHTML = fetchCompetitionHTML(
            url: URL(string: "https://cubing.com/competition/\(slug)/regulations?lang=\(cubingLanguage)"),
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
        let main = await mainHTML
        let regulations = await regulationsHTML
        let travel = await travelHTML
        let schedule = await scheduleHTML
        let register = await registerHTML
        let competitors = includeCompetitors
            ? await fetchCompetitionHTML(
                url: URL(string: "https://cubing.com/competition/\(slug)/competitors?lang=\(cubingLanguage)"),
                languageCode: languageCode
            )
            : nil
        let live = includeLive
            ? await fetchCompetitionHTML(
                url: URL(string: "https://cubing.com/live/\(slug)?lang=\(cubingLanguage)"),
                languageCode: languageCode
            )
            : nil

        guard main != nil || travel != nil || schedule != nil else { return nil }

        let overviewBlocks = main.map(extractCubingOverviewBlocks(from:)) ?? []
        let regulationBlocks = regulations.map(extractCubingRegulationBlocks(from:)) ?? []
        let travelBlocks = travel.map(extractCubingTravelBlocks(from:)) ?? []
        let travelMapLocations = travel.map(extractCubingTravelMapLocations(from:)) ?? []
        let scheduleParseStart = Date()
        let scheduleDays = await CompetitionScheduleParseStore.shared.scheduleDays(
            for: "cubing|\(cubingLanguage)|\(slug)",
            forceRefresh: forceRefresh
        ) {
            if let schedule {
                return await extractCubingScheduleDays(from: schedule)
            }
            return []
        }
        let scheduleParseDurationMS = Int(Date().timeIntervalSince(scheduleParseStart) * 1000)
        let scheduleDebugInfo = cubingScheduleDebugInfo(
            from: schedule,
            slug: slug,
            scheduleDays: scheduleDays,
            parseDurationMS: scheduleParseDurationMS
        )
        let scheduleEventSummaries = schedule.map(extractCubingScheduleEventSummaries(from:)) ?? []
        let scheduleIntroHTML = schedule.flatMap(extractCubingScheduleIntroHTML(from:))
        let scheduleCommentHTML = schedule.flatMap(extractCubingScheduleCommentHTML(from:))
        let localizedName = extractCubingLocalizedCompetitionName(from: main ?? schedule ?? regulations ?? travel ?? register)
        let registerBlocks = register.map(extractCubingRegistrationBlocks(from:)) ?? []
        let registrationRequiresSignIn = register.map(cubingPageRequiresLoginHTML(_:)) ?? false
        let competitorPreviews = includeCompetitors
            ? extractCubingCompetitorPreviews(from: competitors)
            : []
        let competitorsCount = includeCompetitors
            ? (extractCubingCompetitorCount(from: competitors)
                ?? extractCubingCompetitorCount(from: schedule))
            : extractCubingCompetitorCount(from: schedule)
        let liveURL = URL(string: "https://cubing.com/live/\(slug)?lang=\(cubingLanguage)")
        let cubingLiveContent = includeLive
            ? await fetchCubingLiveContent(from: live, languageCode: languageCode)
            : nil
        let liveAvailability = includeLive
            ? cubingLiveAvailability(for: competition, liveHTML: live)
            : (availabilityStatus(for: competition, now: Date()) == .ended ? .ended : .upcoming)

        return CompetitionDetailContent(
            overviewBlocks: overviewBlocks,
            noteBlocks: [],
            regulationBlocks: regulationBlocks,
            travelBlocks: travelBlocks,
            travelMapLocations: travelMapLocations,
            registerBlocks: registerBlocks,
            scheduleDays: scheduleDays,
            scheduleEventSummaries: scheduleEventSummaries,
            wcaEvents: [],
            scheduleIntroHTML: scheduleIntroHTML,
            scheduleCommentHTML: scheduleCommentHTML,
            scheduleDebugInfo: scheduleDebugInfo,
            localizedName: localizedName,
            championshipTitles: nil,
            competitorsCount: competitorsCount,
            competitorPreviews: competitorPreviews,
            registrationRequiresSignIn: registrationRequiresSignIn,
            hasRegisterLink: true,
            hasCompetitorsLink: true,
            liveAvailability: liveAvailability,
            liveURLOverride: liveAvailability == .unavailable ? nil : liveURL,
            liveContent: cubingLiveContent,
            wcaLiveContent: nil
        )
    }

    private static func fetchCubingLiveContent(
        from liveHTML: String?,
        languageCode: String
    ) async -> CompetitionLiveContent? {
        guard let liveHTML else { return nil }

        let sumOfRanksURL = firstCompetitionCapture(
            in: liveHTML,
            pattern: #"href=\"([^\"]+/statistics/sum-of-ranks)\""#
        ).flatMap(URL.init(string:))
        let podiumsURL = firstCompetitionCapture(
            in: liveHTML,
            pattern: #"href=\"([^\"]+/podiums)\""#
        ).flatMap(URL.init(string:))

        async let sumOfRanksHTML = fetchCompetitionHTML(
            url: sumOfRanksURL,
            languageCode: languageCode
        )
        async let podiumsHTML = fetchCompetitionHTML(
            url: podiumsURL,
            languageCode: languageCode
        )

        return extractCubingLiveContent(
            from: liveHTML,
            sumOfRanksHTML: await sumOfRanksHTML,
            podiumsHTML: await podiumsHTML
        )
    }

    private static func fetchCompetitionHTML(
        url: URL?,
        languageCode: String
    ) async -> String? {
        guard let url else { return nil }
        let key = "\(languageCode)|\(url.absoluteString)"
        return await CompetitionInFlightRequestStore.shared.html(for: key) {
            await fetchCompetitionHTMLUncoordinated(url: url, languageCode: languageCode)
        }
    }

    private static func fetchCompetitionHTMLUncoordinated(
        url: URL,
        languageCode: String
    ) async -> String? {
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

    nonisolated static func wcaLiveAvailability(
        for lookup: CompetitionWCALiveLookupState
    ) -> CompetitionLiveAvailability {
        switch lookup {
        case .loading: .loading
        case .available: .available
        case .unavailable: .unavailable
        case .failed: .failed
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

    private struct WCAPsychSheetPayload: Decodable {
        struct Ranking: Decodable {
            let name: String
            let userId: Int
            let wcaId: String?
            let countryIso2: String?
            let averageBest: Int
            let averageRank: Int?
            let singleBest: Int
            let singleRank: Int?
            let tiedPrevious: Bool?
            let pos: Int?
        }

        let sortedRankings: [Ranking]
    }

    private struct WCALiveGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let competition: WCALiveCompetitionPayload?
        }

        let data: DataPayload?
    }

    nonisolated private struct WCALiveProbeGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            struct CompetitionPayload: Decodable {
                let id: String
                let name: String
                let wcaId: String?
            }

            let competition: CompetitionPayload?
        }

        let data: DataPayload?
    }

    private struct WCALiveCompetitionPayload: Decodable {
        struct Record: Decodable {
            struct Result: Decodable {
                struct Person: Decodable {
                    struct Country: Decodable {
                        let name: String
                    }

                    let name: String
                    let country: Country
                }

                struct Round: Decodable {
                    struct CompetitionEvent: Decodable {
                        struct Event: Decodable {
                            let id: String
                            let name: String
                        }

                        let event: Event
                    }

                    let id: String
                    let competitionEvent: CompetitionEvent
                }

                let person: Person
                let round: Round
            }

            let id: String
            let tag: String
            let type: String
            let attemptResult: Int
            let result: Result
        }

        struct CompetitionEvent: Decodable {
            struct Event: Decodable {
                let id: String
                let name: String
            }

            struct Round: Decodable {
                struct Format: Decodable {
                    let id: String
                    let numberOfAttempts: Int
                    let sortBy: String
                }

                struct AdvancementCondition: Decodable {
                    let level: Int
                    let type: String
                }

                let id: String
                let name: String
                let active: Bool
                let open: Bool
                let number: Int?
                let format: Format?
                let finished: Bool?
                let advancementCondition: AdvancementCondition?
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
        let competitionRecords: [Record]
        let competitionEvents: [CompetitionEvent]
        let venues: [Venue]
    }

    private struct WCALiveResolvedCompetition: Sendable {
        let competitionID: Int
        let finalURL: URL
    }

    private struct WCALiveRoundGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let round: WCALiveRoundPayload?
        }

        let data: DataPayload?
    }

    nonisolated private struct WCALiveRoundUpdateGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let roundUpdated: WCALiveRoundPayload?
        }

        let data: DataPayload?
    }

    nonisolated private struct WCALiveRoundPayload: Decodable {
        struct CompetitionEventPayload: Decodable {
            struct EventPayload: Decodable {
                let id: String
                let name: String
            }

            let event: EventPayload
        }

        struct FormatPayload: Decodable {
            let id: String
            let numberOfAttempts: Int?
            let sortBy: String?
        }

        struct AdvancementConditionPayload: Decodable {
            let level: Int
            let type: String
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
            let advancing: Bool?
            let advancingQuestionable: Bool?
            let best: Int
            let average: Int
            let attempts: [AttemptPayload]
            let person: PersonPayload
            let singleRecordTag: String?
            let averageRecordTag: String?
        }

        let id: String
        let name: String?
        let finished: Bool?
        let active: Bool?
        let open: Bool?
        let number: Int?
        let competitionEvent: CompetitionEventPayload?
        let format: FormatPayload?
        let advancementCondition: AdvancementConditionPayload?
        let results: [ResultPayload]
    }

    private struct WCALiveCompetitorGraphQLResponse: Decodable {
        struct DataPayload: Decodable {
            let person: WCALiveCompetitorPayload?
        }

        let data: DataPayload?
    }

    private struct WCALiveCompetitorPayload: Decodable {
        struct CountryPayload: Decodable {
            let iso2: String?
        }

        struct ResultPayload: Decodable {
            struct AttemptPayload: Decodable {
                let result: Int
            }

            struct RoundPayload: Decodable {
                struct CompetitionEventPayload: Decodable {
                    struct EventPayload: Decodable {
                        let id: String
                        let name: String
                        let rank: Int?
                    }

                    let event: EventPayload
                }

                struct FormatPayload: Decodable {
                    let id: String
                    let numberOfAttempts: Int
                    let sortBy: String
                }

                let id: String
                let name: String
                let number: Int?
                let competitionEvent: CompetitionEventPayload
                let format: FormatPayload
            }

            let id: String
            let ranking: Int?
            let advancing: Bool?
            let advancingQuestionable: Bool?
            let attempts: [AttemptPayload]
            let best: Int
            let average: Int
            let singleRecordTag: String?
            let averageRecordTag: String?
            let round: RoundPayload
        }

        let id: String
        let name: String
        let wcaId: String?
        let country: CountryPayload?
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
                registeredEventIDs: person.registration?.eventIds ?? [],
                wcaID: person.wcaId,
                countryISO2: person.countryIso2
            )
        }

        return WCAPublicCompetitors(previews: previews, count: acceptedPeople.count)
    }

    private static func fetchWCAPsychPreviews(
        for competition: CompetitionSummary,
        languageCode: String,
        eventID: String?,
        sortBy: String?
    ) async -> [CompetitionCompetitorPsychPreview] {
        guard let eventID,
              !eventID.isEmpty else {
            return []
        }

        var components = URLComponents(
            string: "https://www.worldcubeassociation.org/api/v0/competitions/\(competition.id)/psych-sheet/\(eventID)"
        )
        if let sortBy, sortBy == "single" || sortBy == "average" {
            components?.queryItems = [URLQueryItem(name: "sort_by", value: sortBy)]
        }
        guard let url = components?.url else { return [] }

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
        guard let payload = try? decoder.decode(WCAPsychSheetPayload.self, from: data) else {
            return []
        }

        return payload.sortedRankings.map { ranking in
            let personID = ranking.wcaId ?? "user-\(ranking.userId)"
            let singleText = formattedWCAPsychResult(
                best: ranking.singleBest,
                eventID: eventID,
                type: "single"
            )
            let averageText = ranking.averageBest > 0
                ? formattedWCAPsychResult(best: ranking.averageBest, eventID: eventID, type: "average")
                : nil
            let item = CompetitionPsychItem(
                id: "\(personID)-\(eventID)",
                eventID: eventID,
                rank: ranking.pos ?? 0,
                resultText: averageText ?? singleText,
                singleWorldRank: ranking.singleRank,
                singleResultText: singleText,
                averageResultText: averageText,
                averageWorldRank: ranking.averageRank,
                tiedPrevious: ranking.tiedPrevious ?? false
            )
            return CompetitionCompetitorPsychPreview(
                id: personID,
                name: ranking.name,
                wcaID: ranking.wcaId,
                items: [item],
                region: localizedRegionName(for: ranking.countryIso2, languageCode: languageCode),
                countryISO2: ranking.countryIso2
            )
        }
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
            competitionRecords {
              id
              tag
              type
              attemptResult
              result {
                person { name country { name } }
                round {
                  id
                  competitionEvent { event { id name } }
                }
              }
            }
            competitionEvents {
              id
              event { id name }
              rounds {
                id
                name
                active
                open
                number
                finished
                format { id numberOfAttempts sortBy }
                advancementCondition { level type }
              }
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
                        formatID: round.format?.id,
                        numberOfAttempts: round.format?.numberOfAttempts,
                        sortBy: round.format?.sortBy,
                        isFinished: round.finished,
                        advancementType: round.advancementCondition?.type,
                        advancementLevel: round.advancementCondition?.level,
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
                formatID: round.formatID,
                numberOfAttempts: round.numberOfAttempts,
                sortBy: round.sortBy,
                isFinished: round.isFinished,
                advancementType: round.advancementType,
                advancementLevel: round.advancementLevel,
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
                    let activities = sortedActivities.map { activity in
                        CompetitionWCALiveActivity(
                            id: activity.id,
                            activityCode: activity.activityCode,
                            name: activity.name,
                            startTime: activity.startTime,
                            endTime: activity.endTime,
                            roomColorHex: room.color
                        )
                    }
                    return CompetitionWCALiveRoom(
                        id: room.id,
                        name: room.name,
                        currentActivityName: currentActivity?.name,
                        currentActivityStart: currentActivity?.startTime,
                        currentActivityEnd: currentActivity?.endTime,
                        nextActivityName: nextActivity?.name,
                        nextActivityStart: nextActivity?.startTime,
                        activities: activities
                    )
                }
            )
        }

        let eventIDs = Array(Set(payload.competitionEvents.map { $0.event.id })).sorted()
        let records = payload.competitionRecords.map { record in
            CompetitionWCALiveRecord(
                id: record.id,
                tag: record.tag,
                type: record.type,
                attemptResult: record.attemptResult,
                eventID: record.result.round.competitionEvent.event.id,
                eventName: record.result.round.competitionEvent.event.name,
                roundID: record.result.round.id,
                personName: record.result.person.name,
                countryName: record.result.person.country.name
            )
        }

        return CompetitionWCALiveContent(
            competitionID: resolved.competitionID,
            competitionName: payload.name,
            eventIDs: eventIDs,
            rounds: hydratedRounds,
            venues: venues,
            records: records
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
              advancing
              advancingQuestionable
              best
              average
              attempts { result }
              singleRecordTag
              averageRecordTag
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

        return competitionWCALiveResultPreviews(from: round.results)
    }

    private static func fetchWCALiveRoundSnapshot(
        roundID: String,
        languageCode: String,
        fallback: CompetitionWCALiveRound
    ) async -> CompetitionWCALiveRound? {
        let query = """
        query Round($id: ID!) {
          round(id: $id) {
            id
            name
            finished
            active
            open
            number
            competitionEvent { event { id name } }
            format { id numberOfAttempts sortBy }
            advancementCondition { level type }
            results {
              id
              ranking
              advancing
              advancingQuestionable
              best
              average
              attempts { result }
              singleRecordTag
              averageRecordTag
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
              200 ..< 300 ~= httpResponse.statusCode,
              let graph = try? JSONDecoder().decode(WCALiveRoundGraphQLResponse.self, from: data),
              let round = graph.data?.round else {
            return nil
        }

        return competitionWCALiveRound(from: round, fallback: fallback)
    }

    nonisolated private static func competitionWCALiveRound(
        from payload: WCALiveRoundPayload,
        fallback: CompetitionWCALiveRound
    ) -> CompetitionWCALiveRound {
        CompetitionWCALiveRound(
            id: payload.id,
            eventID: payload.competitionEvent?.event.id ?? fallback.eventID,
            eventName: payload.competitionEvent?.event.name ?? fallback.eventName,
            roundName: payload.name ?? fallback.roundName,
            number: payload.number ?? fallback.number,
            formatID: payload.format?.id ?? fallback.formatID,
            numberOfAttempts: payload.format?.numberOfAttempts ?? fallback.numberOfAttempts,
            sortBy: payload.format?.sortBy ?? fallback.sortBy,
            isFinished: payload.finished ?? fallback.isFinished,
            advancementType: payload.advancementCondition?.type ?? fallback.advancementType,
            advancementLevel: payload.advancementCondition?.level ?? fallback.advancementLevel,
            isActive: payload.active ?? fallback.isActive,
            isOpen: payload.open ?? fallback.isOpen,
            results: competitionWCALiveResultPreviews(from: payload.results)
        )
    }

    nonisolated private static func competitionWCALiveResultPreviews(
        from results: [WCALiveRoundPayload.ResultPayload]
    ) -> [CompetitionWCALiveResultPreview] {
        // WCA Live creates an empty Result for each round participant before attempts are entered.
        results
            .map { result in
                CompetitionWCALiveResultPreview(
                    id: result.id,
                    ranking: result.ranking.flatMap { $0 > 0 ? $0 : nil },
                    personID: result.person.id,
                    name: result.person.name,
                    region: result.person.country?.name,
                    attempts: result.attempts.map(\.result),
                    best: result.best,
                    average: result.average,
                    isAdvancing: result.advancing,
                    isAdvancingQuestionable: result.advancingQuestionable,
                    singleRecordTag: result.singleRecordTag,
                    averageRecordTag: result.averageRecordTag
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.ranking, rhs.ranking) {
                case let (left?, right?) where left != right:
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func fetchWCALiveCompetitor(
        personID: String,
        languageCode: String
    ) async -> CompetitionWCALiveCompetitorContent? {
        let query = """
        query Competitor($id: ID!) {
          person(id: $id) {
            id
            name
            wcaId
            country { iso2 }
            results {
              id
              ranking
              advancing
              advancingQuestionable
              attempts { result }
              best
              average
              singleRecordTag
              averageRecordTag
              round {
                id
                name
                number
                competitionEvent {
                  event { id name rank }
                }
                format { id numberOfAttempts sortBy }
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": personID]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

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
        guard let graph = try? decoder.decode(WCALiveCompetitorGraphQLResponse.self, from: data),
              let person = graph.data?.person else {
            return nil
        }

        let results = person.results
            .filter { !$0.attempts.isEmpty }
            .map { result in
                CompetitionWCALiveCompetitorResult(
                    id: result.id,
                    ranking: result.ranking,
                    isAdvancing: result.advancing,
                    isAdvancingQuestionable: result.advancingQuestionable,
                    attempts: result.attempts.map(\.result),
                    best: result.best,
                    average: result.average,
                    singleRecordTag: result.singleRecordTag,
                    averageRecordTag: result.averageRecordTag,
                    roundID: result.round.id,
                    roundName: result.round.name,
                    roundNumber: result.round.number,
                    eventID: result.round.competitionEvent.event.id,
                    eventName: result.round.competitionEvent.event.name,
                    eventRank: result.round.competitionEvent.event.rank,
                    formatID: result.round.format.id,
                    numberOfAttempts: result.round.format.numberOfAttempts,
                    sortBy: result.round.format.sortBy
                )
            }
            .sorted { lhs, rhs in
                if (lhs.eventRank ?? Int.max) != (rhs.eventRank ?? Int.max) {
                    return (lhs.eventRank ?? Int.max) < (rhs.eventRank ?? Int.max)
                }
                return (lhs.roundNumber ?? Int.max) < (rhs.roundNumber ?? Int.max)
            }

        return CompetitionWCALiveCompetitorContent(
            id: person.id,
            name: person.name,
            wcaID: person.wcaId,
            countryISO2: person.country?.iso2,
            results: results
        )
    }

    private static func resolveWCALiveCompetition(
        for competition: CompetitionSummary,
        languageCode: String,
        liveURL: URL?
    ) async -> WCALiveResolvedCompetition? {
        let mapping = await resolveWCALiveCompetitionMapping(
            for: competition,
            languageCode: languageCode,
            hintedURL: liveURL
        )
        guard case let .available(competitionID, url) = mapping else {
            return nil
        }
        return WCALiveResolvedCompetition(competitionID: competitionID, finalURL: url)
    }

    private static func lookupWCALiveCompetition(
        for competition: CompetitionSummary,
        languageCode: String,
        hintedURL: URL?,
        forceRefresh: Bool
    ) async -> CompetitionWCALiveLookupState {
        await CompetitionWCALiveLookupStore.shared.lookup(
            for: competition.id,
            forceRefresh: forceRefresh
        ) {
            await performWCALiveCompetitionLookup(
                for: competition,
                languageCode: languageCode,
                hintedURL: hintedURL
            )
        }
    }

    private static func performWCALiveCompetitionLookup(
        for competition: CompetitionSummary,
        languageCode: String,
        hintedURL: URL?
    ) async -> CompetitionWCALiveLookupState {
        let mapping = await resolveWCALiveCompetitionMapping(
            for: competition,
            languageCode: languageCode,
            hintedURL: hintedURL
        )
        guard case let .available(competitionID, finalURL) = mapping else {
            return mapping
        }

        let query = """
        query CompetitionAvailability($id: ID!) {
          competition(id: $id) {
            id
            name
            wcaId
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["id": String(competitionID)]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failed
        }

        var request = URLRequest(url: URL(string: "https://live.worldcubeassociation.org/api")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failed }
            guard 200 ..< 300 ~= httpResponse.statusCode else {
                return httpResponse.statusCode == 404 ? .unavailable : .failed
            }
            guard let decoded = try? JSONDecoder().decode(WCALiveProbeGraphQLResponse.self, from: data) else {
                return .failed
            }
            guard decoded.data?.competition != nil else { return .unavailable }
            guard wcaLiveProbeMatchesCompetition(data, wcaCompetitionID: competition.id) else {
                return .unavailable
            }
            return .available(competitionID: competitionID, url: finalURL)
        } catch {
            return .failed
        }
    }

    private static func resolveWCALiveCompetitionMapping(
        for competition: CompetitionSummary,
        languageCode: String,
        hintedURL: URL?
    ) async -> CompetitionWCALiveLookupState {
        if let hintedURL,
           let competitionID = extractWCALiveCompetitionID(from: hintedURL) {
            guard let canonicalURL = canonicalWCALiveCompetitionURL(for: competitionID) else {
                return .failed
            }
            return .available(competitionID: competitionID, url: canonicalURL)
        }

        guard let mappingURL = hintedURL
            ?? URL(string: "https://live.worldcubeassociation.org/link/competitions/\(competition.id)") else {
            return .failed
        }

        var request = URLRequest(url: mappingURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(appAcceptLanguageHeader(for: languageCode), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failed }
            guard 200 ..< 300 ~= httpResponse.statusCode else {
                return httpResponse.statusCode == 404 ? .unavailable : .failed
            }
            guard let finalURL = response.url,
                  let competitionID = extractWCALiveCompetitionID(from: finalURL) else {
                return .unavailable
            }
            guard let canonicalURL = canonicalWCALiveCompetitionURL(for: competitionID) else {
                return .failed
            }
            return .available(competitionID: competitionID, url: canonicalURL)
        } catch {
            return .failed
        }
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

    private static func canonicalWCALiveCompetitionURL(for competitionID: Int) -> URL? {
        URL(string: "https://live.worldcubeassociation.org/competitions/\(competitionID)")
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
        competition.cubingChinaCompetitionSlug
    }

    private static func hasWCARegisterLink(from html: String, competitionID: String) -> Bool {
        let escapedID = NSRegularExpression.escapedPattern(for: competitionID)
        let patterns = [
            #"(?is)href=['\"]/competitions/\#(escapedID)/register(?:[?'\"]|$)"#,
            #"(?is)href=['\"]https://www\.worldcubeassociation\.org/competitions/\#(escapedID)/register(?:[?'\"]|$)"#
        ]
        return patterns.contains { html.range(of: $0, options: .regularExpression) != nil }
    }

    private static func hasWCACompetitorsLink(from html: String, competitionID: String) -> Bool {
        let escapedID = NSRegularExpression.escapedPattern(for: competitionID)
        let patterns = [
            #"(?is)href=['\"]/competitions/\#(escapedID)/registrations(?:[?'\"]|$)"#,
            #"(?is)href=['\"]https://www\.worldcubeassociation\.org/competitions/\#(escapedID)/registrations(?:[?'\"]|$)"#
        ]
        return patterns.contains { html.range(of: $0, options: .regularExpression) != nil }
    }

    private static func extractWCATabBlocks(from html: String, languageCode: String) -> [CompetitionDetailTextBlock] {
        let tabLinks = extractWCATabLinks(from: html)
        let seenOrderedIDs = tabLinks.reduce(into: Set<String>()) { $0.insert($1.id) }
        let fallbackTitles = extractWCATabTitleMap(from: html)
        let paneIDs = tabLinks.map(\.id) + fallbackTitles.keys.filter { !seenOrderedIDs.contains($0) }.sorted()

        let eventsInformationHTML = extractWCAScheduleLegendHTML(from: html)

        return paneIDs.compactMap { paneID in
            var paneHTML = normalizeWCAPaneHTML(
                extractWCATabPaneHTML(from: html, paneID: paneID) ?? "",
                languageCode: languageCode
            )
            if ["competition-events", "competition-schedule"].contains(paneID),
               !eventsInformationHTML.isEmpty {
                paneHTML += "\n\(eventsInformationHTML)"
            }
            let body = cleanedCompetitionHTMLText(paneHTML)
            let title = tabLinks.first { $0.id == paneID }?.title
                ?? fallbackTitles[paneID]
                ?? fallbackWCATabTitle(for: paneID)
            let isKnownStructuralTab = ["general-info", "competition-events", "competition-schedule"].contains(paneID)
            guard !body.isEmpty || isKnownStructuralTab else { return nil }

            return CompetitionDetailTextBlock(
                id: "wca-\(paneID)",
                title: title,
                body: body,
                html: paneHTML.isEmpty ? nil : paneHTML
            )
        }
    }

    nonisolated static func extractWCAScheduleLegendHTML(from html: String) -> String {
        guard let content = firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<div\b[^>]*class=['\"][^'\"]*\btime-limit-information\b[^'\"]*['\"][^>]*>(.*?)</div>"#
        ) else {
            return ""
        }
        return "<div class=\"time-limit-information\">\(content)</div>"
    }

    private static func extractWCAChampionshipTitles(from html: String) -> [String] {
        let captures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<span\b(?=[^>]*\bclass=['\"][^'\"]*\bchampionship-trophy\b[^'\"]*['\"])(?=[^>]*\btitle=['\"]([^'\"]+)['\"])[^>]*>"#
        )

        var seen = Set<String>()
        return captures.compactMap { capture in
            guard let rawTitle = capture.first else { return nil }
            let title = decodeCompetitionHTMLEntities(rawTitle)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title).inserted else { return nil }
            return title
        }
    }

    private static func normalizeWCAPaneHTML(_ html: String, languageCode: String) -> String {
        var normalized = html
            .replacingOccurrences(
                of: #"(?is)<div\b[^>]*id=['\"](?:show|hide)_(?:registration_requirements|highlights)['\"][^>]*>.*?</div>"#,
                with: "",
                options: .regularExpression
            )

        let pattern = #"(?is)<span\b[^>]*class=['\"][^'\"]*wca-local-time[^'\"]*['\"][^>]*data-utc-time=['\"]([^'\"]+)['\"][^>]*>.*?</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return normalized }

        let formatter = DateFormatter()
        formatter.locale = appLocale(for: languageCode)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let source = normalized as NSString
        let result = NSMutableString(string: normalized)
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: source.length)).reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let rawDate = source.substring(with: match.range(at: 1))
            let date = competitionISO8601Formatter.date(from: rawDate)
                ?? ISO8601DateFormatter().date(from: rawDate)
            guard let date else { continue }
            result.replaceCharacters(in: match.range(at: 0), with: formatter.string(from: date))
        }
        normalized = result as String
        return normalized
    }

    private static func extractWCATabLinks(from html: String) -> [(id: String, title: String)] {
        let patterns = [
            ##"(?is)<a[^>]+href="#([^"]+)"[^>]*data-toggle="tab"[^>]*>(.*?)</a>"##,
            ##"(?is)<a[^>]+data-toggle="tab"[^>]+href="#([^"]+)"[^>]*>(.*?)</a>"##,
            ##"(?is)<button[^>]+data-bs-target="#([^"]+)"[^>]*>(.*?)</button>"##,
            ##"(?is)<button[^>]+data-target="#([^"]+)"[^>]*>(.*?)</button>"##
        ]
        var links: [(id: String, title: String)] = []
        var seenIDs = Set<String>()

        for pattern in patterns {
            for capture in competitionHTMLCaptures(in: html, pattern: pattern) where capture.count >= 2 {
                let paneID = capture[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cleanedCompetitionHTMLText(capture[1])
                guard !paneID.isEmpty, !title.isEmpty, !seenIDs.contains(paneID) else { continue }
                seenIDs.insert(paneID)
                links.append((paneID, title))
            }
        }

        return links
    }

    private static func extractWCATabTitleMap(from html: String) -> [String: String] {
        extractWCATabLinks(from: html).reduce(into: [String: String]()) { titlesByID, link in
            titlesByID[link.id] = link.title
        }
    }

    private static func extractWCATabPaneHTML(from html: String, paneID: String) -> String? {
        let escapedID = NSRegularExpression.escapedPattern(for: paneID)
        let pattern = #"(?is)<div[^>]*class=['\"][^'\"]*\btab-pane\b[^'\"]*['\"][^>]*id=['\"]\#(escapedID)['\"][^>]*>"#
            + #"|(?is)<div[^>]*id=['\"]\#(escapedID)['\"][^>]*class=['\"][^'\"]*\btab-pane\b[^'\"]*['\"][^>]*>"#
        guard let openingRange = html.range(of: pattern, options: .regularExpression) else { return nil }

        var depth = 1
        var searchIndex = openingRange.upperBound
        let tagPattern = #"(?is)</?div\b[^>]*>"#

        while let tagRange = html[searchIndex...].range(of: tagPattern, options: .regularExpression) {
            let tag = html[tagRange].lowercased()
            if tag.hasPrefix("</div") {
                depth -= 1
                if depth == 0 {
                    return String(html[openingRange.upperBound..<tagRange.lowerBound])
                }
            } else {
                depth += 1
            }
            searchIndex = tagRange.upperBound
        }

        return nil
    }

    private static func fallbackWCATabTitle(for paneID: String) -> String {
        paneID
            .replacingOccurrences(of: #"^[0-9]+-"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "competition-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func extractWCARegisterBlocks(from html: String, languageCode: String) -> [CompetitionDetailTextBlock] {
        var blocks: [CompetitionDetailTextBlock] = []

        let requirementsCaptures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)<p>\s*<b>(Registration requirements for the competition:)</b>\s*</p>(.*?)(?:<h2>|<hr\s*/?>)"#
        )
        if let requirements = requirementsCaptures.first,
           requirements.count >= 2 {
            let title = cleanedCompetitionHTMLText(requirements[0])
            let requirementsHTML = requirements[1]
            let body = cleanedCompetitionHTMLText(requirementsHTML)
            if !body.isEmpty {
                blocks.append(
                    CompetitionDetailTextBlock(
                        id: "wca-register-requirements",
                        title: title,
                        body: body,
                        html: requirementsHTML
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
                    body: body,
                    html: capture[1]
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

    private static func extractWCAEvents(from html: String) -> [CompetitionWCAEvent] {
        guard let propsHTML = wcaReactComponentProps(named: "EventsTable", in: html) else {
            return []
        }

        let jsonString = decodeCompetitionHTMLEntities(propsHTML)
        guard let data = jsonString.data(using: .utf8),
              let props = try? JSONDecoder().decode(WCAEventsProps.self, from: data) else {
            return []
        }

        return props.wcifEvents.map { event in
            CompetitionWCAEvent(
                id: event.id,
                rounds: event.rounds.map { round in
                    CompetitionWCAEventRound(
                        id: round.id,
                        formatID: round.format,
                        timeLimitCentiseconds: round.timeLimit?.centiseconds,
                        cumulativeRoundIDs: round.timeLimit?.cumulativeRoundIds ?? [],
                        cutoffAttempts: round.cutoff?.numberOfAttempts,
                        cutoffResult: round.cutoff?.attemptResult,
                        advancementType: round.advancementCondition?.type
                            ?? round.participationRuleset?.participationSource.resultCondition?.type,
                        advancementLevel: round.advancementCondition?.level
                            ?? round.participationRuleset?.participationSource.resultCondition?.value
                    )
                },
                qualification: event.qualification.map {
                    CompetitionWCAQualification(
                        whenDate: $0.whenDate,
                        type: $0.type,
                        resultType: $0.resultType,
                        level: $0.level
                    )
                },
                showsCutoffColumn: props.competitionInfo?.usesCutoff ?? false,
                showsQualificationColumn: props.competitionInfo?.usesQualification ?? false
            )
        }
    }

    static func decodeWCAScheduleDays(from html: String, languageCode: String) -> [CompetitionScheduleDay] {
        guard let propsHTML = wcaReactComponentProps(named: "Schedule", in: html) else {
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

        let roundsByID = Dictionary(
            uniqueKeysWithValues: extractWCAEvents(from: html)
                .flatMap(\.rounds)
                .map { ($0.id, $0) }
        )
        var groupedEntries: [String: [CompetitionScheduleEntry]] = [:]
        var groupedVenues: [String: [CompetitionScheduleVenue]] = [:]

        for venue in props.wcifSchedule.venues {
            let timezone = TimeZone(identifier: venue.timezone) ?? .current
            formatter.timeZone = timezone
            timeFormatter.timeZone = timezone

            for room in venue.rooms {
                var roomEntriesByDay: [String: [CompetitionScheduleEntry]] = [:]
                for activity in room.activities {
                    // The public WCA schedule renders parent activities. Child
                    // activities are competitor groups and must not become
                    // overlapping calendar blocks.
                    let dateKey = formatter.string(from: activity.startTime)
                    let entry = wcaScheduleEntry(
                        from: activity,
                        venue: venue,
                        room: room,
                        timeFormatter: timeFormatter,
                        roundsByID: roundsByID,
                        languageCode: languageCode
                    )
                    groupedEntries[dateKey, default: []].append(entry)
                    roomEntriesByDay[dateKey, default: []].append(entry)
                }

                for (dateKey, entries) in roomEntriesByDay {
                    let venueTitle = venue.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let roomTitle = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = roomTitle.isEmpty ? venueTitle : roomTitle
                    groupedVenues[dateKey, default: []].append(
                        CompetitionScheduleVenue(
                            id: "wca-\(dateKey)-\(venue.id)-\(room.id)",
                            title: title,
                            entries: entries.sorted { lhs, rhs in
                                (lhs.startTime ?? .distantPast) < (rhs.startTime ?? .distantPast)
                            }
                        )
                    )
                }
            }
        }

        return groupedEntries.keys.sorted().map { key in
            CompetitionScheduleDay(
                id: "wca-\(key)",
                title: key,
                entries: groupedEntries[key, default: []].sorted { lhs, rhs in
                    (lhs.startTime ?? .distantPast) < (rhs.startTime ?? .distantPast)
                },
                venues: groupedVenues[key, default: []]
            )
        }
    }

    private static func wcaReactComponentProps(named componentName: String, in html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: componentName)
        let legacyPattern = #"data-react-class=[\"']\#(escapedName)[\"'][^>]*data-react-props=[\"']([^\"']+)[\"']"#
        if let legacyProps = firstCompetitionCapture(in: html, pattern: legacyPattern) {
            return legacyProps
        }

        // React on Rails now emits component props in an adjacent JSON script.
        let scriptPattern = #"(?is)<script\b(?=[^>]*\bdata-component-name=[\"']\#(escapedName)[\"'])[^>]*>(.*?)</script>"#
        return firstCompetitionCapture(in: html, pattern: scriptPattern)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wcaScheduleEntry(
        from activity: WCAActivity,
        venue: WCAVenue,
        room: WCARoom,
        timeFormatter: DateFormatter,
        roundsByID: [String: CompetitionWCAEventRound],
        languageCode: String
    ) -> CompetitionScheduleEntry {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeFormatter.timeZone ?? .current
        let startComponents = calendar.dateComponents([.hour, .minute], from: activity.startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: activity.endTime)
        let startMinuteOfDay = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinuteOfDay = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        let components = activity.activityCode.split(separator: "-").map(String.init)
        let eventCode = components.first.flatMap { code in
            code == "other" ? nil : code
        }
        let roundID = components.firstIndex(where: { $0.hasPrefix("r") }).map { index in
            components.prefix(index + 1).joined(separator: "-")
        }
        let round = roundID.flatMap { id in
            id.split(separator: "r").last.flatMap { Int($0) }
        }
        let roundDetails = roundID.flatMap { roundsByID[$0] }
        let title = eventCode == nil
            ? activity.name
            : activity.name.components(separatedBy: ", Round").first ?? activity.name
        let roomName = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let venueName = venue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayedRoomName = roomName.isEmpty ? venueName : roomName

        return CompetitionScheduleEntry(
            id: "wca-activity-\(activity.id)",
            timeText: "\(timeFormatter.string(from: activity.startTime))–\(timeFormatter.string(from: activity.endTime))",
            title: title,
            detailText: displayedRoomName,
            venueName: displayedRoomName,
            roomID: String(room.id),
            eventCode: eventCode,
            // Public WCA schedule rows are parent activities. Their child
            // activities contain competitor groups, but the official table
            // deliberately does not expose those groups as a column.
            group: nil,
            round: round.map { value in
                String(
                    format: appLocalizedString(
                        "competitions.wca.round.number_format",
                        languageCode: languageCode,
                        defaultValue: "Round %d"
                    ),
                    value
                )
            },
            format: roundDetails.map { localizedWCAFormat($0.formatID, languageCode: languageCode) },
            cutoff: roundDetails.flatMap { localizedWCACutoff($0, eventID: eventCode, languageCode: languageCode) },
            timeLimit: roundDetails.flatMap { localizedWCATimeLimit($0, languageCode: languageCode) },
            advancingCount: roundDetails.flatMap { localizedWCAAdvancement($0, languageCode: languageCode) },
            startTime: activity.startTime,
            endTime: activity.endTime,
            roomColorHex: room.color,
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay
        )
    }

    private static func localizedWCAFormat(_ formatID: String, languageCode: String) -> String {
        let key: String
        let fallback: String
        switch formatID {
        case "1": (key, fallback) = ("competitions.wca.format.best_of_1", "Best of 1")
        case "2": (key, fallback) = ("competitions.wca.format.best_of_2", "Best of 2")
        case "3": (key, fallback) = ("competitions.wca.format.best_of_3", "Best of 3")
        case "5": (key, fallback) = ("competitions.wca.format.best_of_5", "Best of 5")
        case "m": (key, fallback) = ("competitions.wca.format.mean_of_3", "Mean of 3")
        default: (key, fallback) = ("competitions.wca.format.average_of_5", "Average of 5")
        }
        return appLocalizedString(key, languageCode: languageCode, defaultValue: fallback)
    }

    private static func localizedWCATimeLimit(
        _ round: CompetitionWCAEventRound,
        languageCode: String
    ) -> String? {
        guard let centiseconds = round.timeLimitCentiseconds else { return nil }
        let duration = formattedWCADuration(centiseconds)
        guard !round.cumulativeRoundIDs.isEmpty else { return duration }
        return String(
            format: appLocalizedString(
                "competitions.wca.time_limit.cumulative_format",
                languageCode: languageCode,
                defaultValue: "%@ cumulative"
            ),
            duration
        )
    }

    private static func localizedWCACutoff(
        _ round: CompetitionWCAEventRound,
        eventID: String?,
        languageCode: String
    ) -> String? {
        guard let attempts = round.cutoffAttempts,
              let result = round.cutoffResult else { return nil }
        let resultText = formattedWCAPsychResult(best: result, eventID: eventID ?? "", type: "single")
        return String(
            format: appLocalizedString(
                "competitions.wca.cutoff_format",
                languageCode: languageCode,
                defaultValue: "%@ in %d attempts"
            ),
            resultText,
            attempts
        )
    }

    private static func localizedWCAAdvancement(
        _ round: CompetitionWCAEventRound,
        languageCode: String
    ) -> String? {
        guard let type = round.advancementType,
              let level = round.advancementLevel else { return nil }
        switch type {
        case "ranking":
            return String(
                format: appLocalizedString(
                    "competitions.wca.advancement.ranking_format",
                    languageCode: languageCode,
                    defaultValue: "Top %d"
                ),
                level
            )
        case "percent":
            return String(
                format: appLocalizedString(
                    "competitions.wca.advancement.percent_format",
                    languageCode: languageCode,
                    defaultValue: "Top %d%%"
                ),
                level
            )
        default:
            return formattedWCAPsychResult(best: level, eventID: "", type: "single")
        }
    }

    private static func formattedWCADuration(_ centiseconds: Int) -> String {
        let totalSeconds = max(centiseconds, 0) / 100
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func extractCubingOverviewBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        appendingCubingDisclaimer(
            from: html,
            to: extractCubingDefinitionListBlocks(
            from: html,
            idPrefix: "cubing-main",
            fallbackID: "cubing-main-page",
            fallbackTitle: nil
            ),
            id: "cubing-main-disclaimer"
        )
    }

    private static func extractCubingRegulationBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        appendingCubingDisclaimer(
            from: html,
            to: extractCubingDefinitionListBlocks(
                from: html,
                idPrefix: "cubing-regulations",
                fallbackID: "cubing-regulations",
                fallbackTitle: nil
            ),
            id: "cubing-regulations-disclaimer"
        )
    }

    private static func extractCubingTravelBlocks(from html: String) -> [CompetitionDetailTextBlock] {
        let definitionBlocks = extractCubingDefinitionListBlocks(
            from: html,
            idPrefix: "cubing-travel",
            fallbackID: "cubing-travel",
            fallbackTitle: nil
        )
        if !definitionBlocks.isEmpty {
            return appendingCubingDisclaimer(from: html, to: definitionBlocks, id: "cubing-travel-disclaimer")
        }

        let contentHTML = primaryCubingPageContentHTML(from: html) ?? html
        return appendingCubingDisclaimer(
            from: html,
            to: extractCubingHeadingBlocks(
                from: contentHTML,
                idPrefix: "cubing-travel",
                fallbackID: "cubing-travel",
                fallbackTitle: nil
            ),
            id: "cubing-travel-disclaimer"
        )
    }

    private static func extractCubingTravelMapLocations(from html: String) -> [CompetitionTravelMapLocation] {
        let captures = competitionHTMLCaptures(
            in: html,
            pattern: #"(?is)(<div\b[^>]*class=['\"][^'\"]*\blocation-map\b[^'\"]*['\"][^>]*>)"#
        )

        return captures.enumerated().compactMap { index, capture -> CompetitionTravelMapLocation? in
            guard let tagHTML = capture.first else { return nil }
            let attributes = htmlAttributes(from: tagHTML)
            guard let latitudeText = attributes["data-latitude"],
                  let longitudeText = attributes["data-longitude"],
                  let latitude = Double(latitudeText),
                  let longitude = Double(longitudeText) else {
                return nil
            }

            let venue = cleanedCompetitionHTMLText(attributes["data-venue"] ?? "")
            let address = cleanedCompetitionHTMLText(attributes["data-address"] ?? "")
            return CompetitionTravelMapLocation(
                id: "cubing-travel-map-\(index)-\(latitude)-\(longitude)",
                latitude: latitude,
                longitude: longitude,
                venue: venue,
                address: address
            )
        }
    }

    private static func htmlAttributes(from tagHTML: String) -> [String: String] {
        let captures = competitionHTMLCaptures(
            in: tagHTML,
            pattern: #"(?is)\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(['\"])(.*?)\2"#
        )
        var attributes: [String: String] = [:]
        for capture in captures where capture.count >= 3 {
            attributes[capture[0].lowercased()] = decodeCompetitionHTMLEntities(capture[2])
        }
        return attributes
    }

    private static func appendingCubingDisclaimer(
        from html: String,
        to blocks: [CompetitionDetailTextBlock],
        id: String
    ) -> [CompetitionDetailTextBlock] {
        guard let disclaimer = extractCubingDisclaimerBlock(from: html, id: id) else {
            return blocks
        }
        guard !blocks.contains(where: { $0.body == disclaimer.body }) else {
            return blocks
        }
        return blocks + [disclaimer]
    }

    private static func extractCubingDisclaimerBlock(from html: String, id: String) -> CompetitionDetailTextBlock? {
        guard let disclaimerHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<p>\s*Cubing China is an information sharing platform.*?</p>"#
        ) else {
            return nil
        }
        let sanitizedHTML = sanitizedCubingContentHTML(disclaimerHTML)
        let body = cleanedCompetitionHTMLText(sanitizedHTML)
        guard !body.isEmpty else { return nil }
        return CompetitionDetailTextBlock(id: id, title: nil, body: body, html: sanitizedHTML)
    }

    private static func extractCubingDefinitionListBlocks(
        from html: String,
        idPrefix: String,
        fallbackID: String,
        fallbackTitle: String?
    ) -> [CompetitionDetailTextBlock] {
        let contentHTML = primaryCubingPageContentHTML(from: html) ?? html
        let captures = competitionHTMLCaptures(
            in: contentHTML,
            pattern: #"(?is)<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)(?=<dt\b|</dl>)"#
        )

        let blocks = captures.enumerated().compactMap { index, capture -> CompetitionDetailTextBlock? in
            guard capture.count >= 2 else { return nil }
            let title = cleanedCompetitionHTMLText(sanitizedCubingContentHTML(capture[0]))
            let bodyHTML = sanitizedCubingContentHTML(capture[1])
            let body = cleanedCompetitionHTMLText(bodyHTML)
            guard !body.isEmpty else { return nil }
            return CompetitionDetailTextBlock(
                id: "\(idPrefix)-\(index)",
                title: title.isEmpty ? nil : title,
                body: body,
                html: bodyHTML
            )
        }

        if !blocks.isEmpty {
            return blocks
        }

        let fallbackHTML = sanitizedCubingContentHTML(contentHTML)
        let fallbackBody = cleanedCompetitionHTMLText(fallbackHTML)
        guard !fallbackBody.isEmpty else { return [] }
        return [
            CompetitionDetailTextBlock(
                id: fallbackID,
                title: fallbackTitle,
                body: fallbackBody,
                html: fallbackHTML
            )
        ]
    }

    private static func extractCubingHeadingBlocks(
        from html: String,
        idPrefix: String,
        fallbackID: String,
        fallbackTitle: String?
    ) -> [CompetitionDetailTextBlock] {
        let contentHTML = sanitizedCubingContentHTML(html)
        let captures = competitionHTMLCaptures(
            in: contentHTML,
            pattern: #"(?is)<h([1-4])[^>]*>(.*?)</h\1>\s*(.*?)(?=<h[1-4]\b|</dl>|$)"#
        )

        let blocks = captures.enumerated().compactMap { index, capture -> CompetitionDetailTextBlock? in
            guard capture.count >= 3 else { return nil }
            let title = cleanedCompetitionHTMLText(capture[1])
            let bodyHTML = sanitizedCubingContentHTML(capture[2])
            let body = cleanedCompetitionHTMLText(bodyHTML)
            guard !title.isEmpty || !body.isEmpty else { return nil }
            return CompetitionDetailTextBlock(
                id: "\(idPrefix)-\(index)",
                title: title.isEmpty ? nil : title,
                body: body,
                html: bodyHTML
            )
        }

        if !blocks.isEmpty {
            return blocks
        }

        let fallbackBody = cleanedCompetitionHTMLText(contentHTML)
        guard !fallbackBody.isEmpty else { return [] }
        return [
            CompetitionDetailTextBlock(
                id: fallbackID,
                title: fallbackTitle,
                body: fallbackBody,
                html: contentHTML
            )
        ]
    }

    private static func primaryCubingPageContentHTML(from html: String) -> String? {
        firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<div class=\"page-content\">(.*?)(?:<footer\b|</body>)"#
        )
    }

    private static func sanitizedCubingContentHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<script\b.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<div[^>]*class=\"[^\"]*countdown-timer[^\"]*\".*?(?=<dt\b|</dd>|</dl>|$)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<span[^>]*class=\"btn[^\"]*\"[^>]*>.*?</span>"#, with: "", options: .regularExpression)
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

    private static func extractCubingScheduleEventSummaries(from html: String) -> [CompetitionScheduleEventSummary] {
        guard let scheduleEventsHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<div\b[^>]*class=[\"'][^\"']*\bschedule-event\b[^\"']*[\"'][^>]*>(.*?)(?=<p\b|<div\b[^>]*class=[\"'][^\"']*\bpanel\b)"#
        ) else {
            return []
        }

        let labelCaptures = competitionHTMLCaptures(
            in: scheduleEventsHTML,
            pattern: #"(?is)<label[^>]*>\s*<input[^>]*data-event=[\"']([^\"']+)[\"'][^>]*>\s*(.*?)</label>"#
        )

        return labelCaptures.enumerated().compactMap { index, capture -> CompetitionScheduleEventSummary? in
            guard capture.count >= 2 else { return nil }
            let eventCode = normalizedCubingScheduleEventCode(capture[0])
            let labelHTML = capture[1]
            let title = cleanedCompetitionHTMLText(
                firstCompetitionCapture(in: labelHTML, pattern: #"(?is)<i[^>]*title=[\"']([^\"']+)[\"'][^>]*>"#) ?? ""
            )
            let detailHTML = labelHTML
                .replacingOccurrences(of: #"(?is)<i[^>]*class=[\"'][^\"']*event-icon[^\"']*[\"'][^>]*></i>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)<i[^>]*class=[\"'][^\"']*fa-rmb[^\"']*[\"'][^>]*></i>"#, with: "¥", options: .regularExpression)
            let detail = cleanedCompetitionHTMLText(detailHTML)
            guard !detail.isEmpty else { return nil }
            return CompetitionScheduleEventSummary(
                id: "cubing-schedule-event-\(eventCode ?? String(index))-\(index)",
                eventCode: eventCode,
                title: title.isEmpty ? (eventCode ?? "") : title,
                detail: detail
            )
        }
    }

    private static func extractCubingScheduleIntroHTML(from html: String) -> String? {
        let contentHTML = primaryCubingPageContentHTML(from: html) ?? html
        guard let paragraphHTML = firstCompetitionCapture(
            in: contentHTML,
            pattern: #"(?is)</div>\s*<p>(.*?)</p>\s*<div[^>]*class=[\"'][^\"']*\bpanel\b"#
        ) else {
            return nil
        }
        let sanitized = sanitizedCubingContentHTML("<p>\(paragraphHTML)</p>")
        return cleanedCompetitionHTMLText(sanitized).isEmpty ? nil : sanitized
    }

    private static func extractCubingScheduleCommentHTML(from html: String) -> String? {
        guard let commentHTML = firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<div\b[^>]*class=[\"'][^\"']*\bschedule-comment\b[^\"']*[\"'][^>]*>(.*?)</div>"#
        ) else {
            return nil
        }
        let sanitized = sanitizedCubingContentHTML(commentHTML)
        return cleanedCompetitionHTMLText(sanitized).isEmpty ? nil : sanitized
    }

    private static func extractCubingLocalizedCompetitionName(from html: String?) -> String? {
        guard let html else { return nil }
        let rawTitle = firstCompetitionCapture(
            in: html,
            pattern: #"(?is)<h1\b[^>]*class=[\"'][^\"']*\bheading-title\b[^\"']*[\"'][^>]*>(.*?)</h1>"#
        ) ?? firstCompetitionCapture(in: html, pattern: #"(?is)<title>(.*?)</title>"#)
        guard let rawTitle else { return nil }
        let cleaned = cleanedCompetitionHTMLText(rawTitle)
        guard !cleaned.isEmpty else { return nil }
        let separators = [" - ", "-赛程安排", "-Schedule", "-规则", "-规程", "-Regulations", "-交通", "-Travel", "-报名", "-Registration", "-选手", "-Competitors"]
        var name = cleaned
        for separator in separators {
            if let range = name.range(of: separator, options: [.caseInsensitive]) {
                name = String(name[..<range.lowerBound])
                break
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func extractCubingScheduleDays(from html: String) -> [CompetitionScheduleDay] {
        let scheduleHTML = cubingTraditionalScheduleHTML(from: html)
        let sections = cubingSchedulePanelSections(in: scheduleHTML)

        return sections.compactMap { capture in
            let title = capture.title
            let entries = extractCubingScheduleEntries(from: capture.body, dayTitle: title)
            let venues = extractCubingScheduleVenues(from: capture.body, dayTitle: title)

            guard !entries.isEmpty else { return nil }
            return CompetitionScheduleDay(
                id: "cubing-\(title)",
                title: title,
                entries: entries,
                venues: venues
            )
        }
    }

    private static func cubingScheduleDebugInfo(
        from html: String?,
        slug: String,
        scheduleDays: [CompetitionScheduleDay],
        parseDurationMS: Int
    ) -> CompetitionScheduleDebugInfo {
        guard let html else {
            return CompetitionScheduleDebugInfo(
                source: "cubing.com",
                slug: slug,
                htmlLength: 0,
                parseDurationMS: parseDurationMS,
                hasOldStyleSection: false,
                htmlContainsTable: false,
                scheduleContainsTable: false,
                scheduleContainsResponsiveTable: false,
                panelCount: 0,
                tableCount: 0,
                entryCount: 0,
                panelPreview: nil
            )
        }

        let scheduleHTML = cubingTraditionalScheduleHTML(from: html)
        let sections = cubingSchedulePanelSections(in: scheduleHTML)
        let tableCount = sections.reduce(0) { count, section in
            count + cubingScheduleTableCaptures(in: section.body).count
        }
        let entryCount = scheduleDays.reduce(0) { count, day in
            count + day.entries.count
        }

        return CompetitionScheduleDebugInfo(
            source: "cubing.com",
            slug: slug,
            htmlLength: html.count,
            parseDurationMS: parseDurationMS,
            hasOldStyleSection: html.contains(#"id="old-style""#),
            htmlContainsTable: html.localizedCaseInsensitiveContains("<table"),
            scheduleContainsTable: scheduleHTML.localizedCaseInsensitiveContains("<table"),
            scheduleContainsResponsiveTable: scheduleHTML.localizedCaseInsensitiveContains("table-responsive"),
            panelCount: sections.count,
            tableCount: tableCount,
            entryCount: entryCount,
            panelPreview: sections.first.map { cubingScheduleDebugPreview(from: $0.body) }
        )
    }

    private static func cubingScheduleDebugPreview(from html: String) -> String {
        let collapsed = html
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(collapsed.prefix(700))
    }

    private static func extractCubingScheduleEntries(from dayHTML: String, dayTitle: String) -> [CompetitionScheduleEntry] {
        let tableCaptures = cubingScheduleTableCaptures(in: dayHTML)

        return tableCaptures.enumerated().flatMap { tableIndex, capture in
            let rawVenue = cleanedCompetitionHTMLText(capture.venueHTML)
            return extractCubingScheduleEntries(
                from: capture.tableHTML,
                dayTitle: dayTitle,
                venueName: rawVenue.isEmpty ? nil : rawVenue,
                tableIndex: tableIndex
            )
        }
    }

    private struct CubingSchedulePanelSection {
        let title: String
        let body: String
    }

    private static func cubingTraditionalScheduleHTML(from html: String) -> String {
        guard let oldStyleRange = html.range(of: #"id="old-style""#) else {
            return html
        }
        let lowerBound = oldStyleRange.lowerBound
        let upperBound = html[lowerBound...].range(of: #"<div class="schedule-comment""#)?.lowerBound ?? html.endIndex
        return String(html[lowerBound..<upperBound])
    }

    private static func cubingSchedulePanelSections(in html: String) -> [CubingSchedulePanelSection] {
        let pattern = #"(?is)<h3 class=\"panel-title\">(.*?)</h3>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        return matches.enumerated().compactMap { index, match in
            guard match.numberOfRanges > 1 else { return nil }
            let title = cleanedCompetitionHTMLText(nsHTML.substring(with: match.range(at: 1)))
            guard !title.isEmpty else { return nil }
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsHTML.length
            guard start <= end else { return nil }
            return CubingSchedulePanelSection(
                title: title,
                body: nsHTML.substring(with: NSRange(location: start, length: end - start))
            )
        }
    }

    private static func extractCubingScheduleVenues(from dayHTML: String, dayTitle: String) -> [CompetitionScheduleVenue] {
        let tableCaptures = cubingScheduleTableCaptures(in: dayHTML)

        return tableCaptures.enumerated().compactMap { tableIndex, capture in
            let rawVenue = cleanedCompetitionHTMLText(capture.venueHTML)
            let venueTitle = rawVenue.isEmpty ? "赛程" : rawVenue
            let entries = extractCubingScheduleEntries(
                from: capture.tableHTML,
                dayTitle: dayTitle,
                venueName: rawVenue.isEmpty ? nil : rawVenue,
                tableIndex: tableIndex
            )
            guard !entries.isEmpty else { return nil }
            return CompetitionScheduleVenue(
                id: "\(dayTitle)-venue-\(tableIndex)-\(venueTitle)",
                title: venueTitle,
                entries: entries
            )
        }
    }

    private static func cubingScheduleTableCaptures(in dayHTML: String) -> [(venueHTML: String, tableHTML: String)] {
        let responsiveCaptures = competitionHTMLCaptures(
            in: dayHTML,
            pattern: #"(?is)(?:<h3[^>]*>(.*?)</h3>\s*)?<div[^>]*class=["'][^"']*table-responsive[^"']*["'][^>]*>\s*<table[^>]*>(.*?)</table>"#
        )
        let responsiveTables = responsiveCaptures.compactMap { capture -> (venueHTML: String, tableHTML: String)? in
            guard let tableHTML = capture.last else { return nil }
            let venueHTML = capture.count > 1 ? capture[0] : ""
            return (venueHTML, tableHTML)
        }

        if !responsiveTables.isEmpty {
            return responsiveTables
        }

        return competitionHTMLCaptures(
            in: dayHTML,
            pattern: #"(?is)(?:<h3[^>]*>(.*?)</h3>\s*)?<table[^>]*>(.*?)</table>"#
        )
        .compactMap { capture -> (venueHTML: String, tableHTML: String)? in
            guard let tableHTML = capture.last else { return nil }
            let venueHTML = capture.count > 1 ? capture[0] : ""
            return (venueHTML, tableHTML)
        }
    }

    private static func extractCubingScheduleEntries(
        from tableHTML: String,
        dayTitle: String,
        venueName: String?,
        tableIndex: Int
    ) -> [CompetitionScheduleEntry] {
        let headerHTMLs = competitionHTMLCaptures(in: tableHTML, pattern: #"(?is)<th[^>]*>(.*?)</th>"#).compactMap(\.first)
        let headers = headerHTMLs.map(cleanedCompetitionHTMLText)
        let rowHTMLs = competitionHTMLCaptures(in: tableHTML, pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#).compactMap(\.first)

        return rowHTMLs.enumerated().compactMap { rowIndex, rowHTML -> CompetitionScheduleEntry? in
            let cellHTMLs = competitionHTMLCaptures(in: rowHTML, pattern: #"(?is)<td[^>]*>(.*?)</td>"#).compactMap(\.first)
            guard cellHTMLs.count >= 3 else { return nil }
            let cells = cellHTMLs.map(cleanedCompetitionHTMLText)

            let start = cubingScheduleCell(cells: cells, headers: headers, matching: ["开始", "start"])
            let end = cubingScheduleCell(cells: cells, headers: headers, matching: ["结束", "end"])
            let event = normalizedCubingScheduleEventTitle(cubingScheduleCell(cells: cells, headers: headers, matching: ["项目", "event"]))
            guard !event.isEmpty else { return nil }

            let group = cubingScheduleCell(cells: cells, headers: headers, matching: ["分组", "group"])
            let round = cubingScheduleCell(cells: cells, headers: headers, matching: ["轮次", "round"])
            let format = cubingScheduleCell(cells: cells, headers: headers, matching: ["赛制", "format"])
            let cutoff = cubingScheduleCell(cells: cells, headers: headers, matching: ["及格线", "cutoff"])
            let timeLimit = cubingScheduleCell(cells: cells, headers: headers, matching: ["还原时限", "time limit", "limit"])
            let advancingCount = cubingScheduleCell(cells: cells, headers: headers, matching: ["人数", "competitor", "person"])

            var details: [String] = []
            if !group.isEmpty { details.append(group) }
            if !round.isEmpty { details.append(round) }
            if !format.isEmpty { details.append(format) }
            if !cutoff.isEmpty { details.append(cutoff) }
            if !timeLimit.isEmpty { details.append(timeLimit) }
            if !advancingCount.isEmpty { details.append(advancingCount) }

            return CompetitionScheduleEntry(
                id: "\(dayTitle)-\(tableIndex)-\(rowIndex)-\(start)-\(event)",
                timeText: [start, end].filter { !$0.isEmpty }.joined(separator: "–"),
                title: event,
                detailText: details.isEmpty ? nil : details.joined(separator: " · "),
                venueName: venueName,
                eventCode: normalizedCubingScheduleEventCode(
                    firstCompetitionCapture(in: rowHTML, pattern: #"class=\"[^\"]*\bevent-([^\"\s]+)"#)
                ),
                group: group.isEmpty ? nil : group,
                round: round.isEmpty ? nil : round,
                format: format.isEmpty ? nil : format,
                cutoff: cutoff.isEmpty ? nil : cutoff,
                timeLimit: timeLimit.isEmpty ? nil : timeLimit,
                advancingCount: advancingCount.isEmpty ? nil : advancingCount
            )
        }
    }

    private static func cubingScheduleCell(cells: [String], headers: [String], matching keywords: [String]) -> String {
        guard !cells.isEmpty else { return "" }
        if let index = headers.firstIndex(where: { header in
            let normalized = header.lowercased()
            return keywords.contains { normalized.contains($0.lowercased()) }
        }), cells.indices.contains(index) {
            return cells[index]
        }
        return ""
    }

    private static func normalizedCubingScheduleEventCode(_ rawCode: String?) -> String? {
        guard let rawCode else { return nil }
        let normalized = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ICON-", with: "")
            .replacingOccurrences(of: "icon-", with: "")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedCubingScheduleEventTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: #"(?i)\bICON-[A-Z0-9]+\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    nonisolated private static func strippingLocalizedOverrides(_ competition: CompetitionSummary) -> CompetitionSummary {
        CompetitionSummary(
            id: competition.id,
            name: competition.name,
            shortDisplayName: competition.shortDisplayName,
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
            championshipTypes: competition.championshipTypes,
            registrationStatus: competition.registrationStatus,
            localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil,
            localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil
        )
    }

    private static func cacheKey(for query: CompetitionQuery) -> String {
        [
            "competition-query-v3",
            query.languageCode,
            query.region.id,
            query.events.map(\.rawValue).sorted().joined(separator: ","),
            query.year.id,
            query.status.rawValue
        ].joined(separator: "|")
    }

    private static func cacheKeyForTopCubers(competitionID: String) -> String {
        "top-cubers|v2|\(competitionID)"
    }

    private static func cacheKeyForDetail(
        competitionID: String,
        languageCode: String,
        includeCompetitors: Bool,
        includeLive: Bool
    ) -> String {
        "detail|v8|\(languageCode)|\(competitionID)|competitors:\(includeCompetitors)|live:\(includeLive)"
    }
}

private actor CompetitionInFlightRequestStore {
    static let shared = CompetitionInFlightRequestStore()

    private var pageTasks: [String: Task<CompetitionPageResult, Error>] = [:]
    private var detailTasks: [String: Task<CompetitionDetailContent, Never>] = [:]
    private var topCuberTasks: [String: Task<[CompetitionTopCuberPreview]?, Never>] = [:]
    private var registrationSummaryTasks: [String: Task<CompetitionRegistrationSummary?, Never>] = [:]
    private var htmlTasks: [String: Task<String?, Never>] = [:]

    func competitionsPage(
        for key: String,
        loader: @escaping @Sendable () async throws -> CompetitionPageResult
    ) async throws -> CompetitionPageResult {
        if let task = pageTasks[key] {
            return try await task.value
        }

        let task = Task {
            try await loader()
        }
        pageTasks[key] = task
        defer { pageTasks[key] = nil }
        return try await task.value
    }

    func detailContent(
        for key: String,
        loader: @escaping @Sendable () async -> CompetitionDetailContent
    ) async -> CompetitionDetailContent {
        if let task = detailTasks[key] {
            return await task.value
        }

        let task = Task {
            await loader()
        }
        detailTasks[key] = task
        defer { detailTasks[key] = nil }
        return await task.value
    }

    func topCuberPreviews(
        for key: String,
        loader: @escaping @Sendable () async -> [CompetitionTopCuberPreview]?
    ) async -> [CompetitionTopCuberPreview]? {
        if let task = topCuberTasks[key] {
            return await task.value
        }

        let task = Task {
            await loader()
        }
        topCuberTasks[key] = task
        defer { topCuberTasks[key] = nil }
        return await task.value
    }

    func registrationSummary(
        for key: String,
        loader: @escaping @Sendable () async -> CompetitionRegistrationSummary?
    ) async -> CompetitionRegistrationSummary? {
        if let task = registrationSummaryTasks[key] {
            return await task.value
        }

        let task = Task {
            await loader()
        }
        registrationSummaryTasks[key] = task
        defer { registrationSummaryTasks[key] = nil }
        return await task.value
    }

    func html(
        for key: String,
        loader: @escaping @Sendable () async -> String?
    ) async -> String? {
        if let task = htmlTasks[key] {
            return await task.value
        }

        let task = Task {
            await loader()
        }
        htmlTasks[key] = task
        defer { htmlTasks[key] = nil }
        return await task.value
    }

    func clear() {
        pageTasks.removeAll()
        detailTasks.removeAll()
        topCuberTasks.removeAll()
        registrationSummaryTasks.removeAll()
        htmlTasks.removeAll()
    }
}

private actor CompetitionWCALiveLookupStore {
    static let shared = CompetitionWCALiveLookupStore()

    private struct Entry {
        let state: CompetitionWCALiveLookupState
        let cachedAt: Date
    }

    private var entriesByCompetitionID: [String: Entry] = [:]
    private var tasksByCompetitionID: [String: Task<CompetitionWCALiveLookupState, Never>] = [:]

    func lookup(
        for competitionID: String,
        forceRefresh: Bool,
        loader: @escaping @Sendable () async -> CompetitionWCALiveLookupState
    ) async -> CompetitionWCALiveLookupState {
        if let task = tasksByCompetitionID[competitionID] {
            return await task.value
        }

        if !forceRefresh,
           let entry = entriesByCompetitionID[competitionID],
           Date().timeIntervalSince(entry.cachedAt) <= cacheLifetime(for: entry.state) {
            return entry.state
        }

        let task = Task { await loader() }
        tasksByCompetitionID[competitionID] = task
        let state = await task.value
        tasksByCompetitionID[competitionID] = nil

        if case .loading = state {
            // Loading is transient and should never become a cached terminal result.
        } else {
            entriesByCompetitionID[competitionID] = Entry(state: state, cachedAt: Date())
        }
        return state
    }

    func clear() {
        tasksByCompetitionID.values.forEach { $0.cancel() }
        tasksByCompetitionID.removeAll()
        entriesByCompetitionID.removeAll()
    }

    private func cacheLifetime(for state: CompetitionWCALiveLookupState) -> TimeInterval {
        switch state {
        case .available: 6 * 60 * 60
        case .unavailable: 15 * 60
        case .failed: 30
        case .loading: 0
        }
    }
}

private actor CompetitionDetailContentStore {
    static let shared = CompetitionDetailContentStore()

    private struct CacheEntry: Codable {
        let content: CompetitionDetailContent
        let cachedAt: Date
    }

    private let cacheLifetime: TimeInterval = 6 * 60 * 60
    private let maximumEntryCount = 24
    private var entriesByKey: [String: CacheEntry] = [:]
    private var hasLoadedFromDisk = false

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("competition-detail-cache-v2.json")
    }

    private func legacyCacheFileURL() -> URL {
        cacheFileURL().deletingLastPathComponent()
            .appendingPathComponent("competition-detail-cache-v1.json")
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        guard let data = try? Data(contentsOf: cacheFileURL()),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return
        }
        entriesByKey = decoded
        removeExpiredEntries(referenceDate: Date())
    }

    private func removeExpiredEntries(referenceDate: Date) {
        entriesByKey = entriesByKey.filter {
            referenceDate.timeIntervalSince($0.value.cachedAt) <= cacheLifetime
        }
    }

    private func persistToDisk() {
        let url = cacheFileURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entriesByKey)
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache write failure should never prevent competition details from loading.
        }
    }

    func content(for key: String) -> CompetitionDetailContent? {
        loadFromDiskIfNeeded()
        guard let entry = entriesByKey[key] else { return nil }
        guard Date().timeIntervalSince(entry.cachedAt) <= cacheLifetime else {
            entriesByKey[key] = nil
            persistToDisk()
            return nil
        }
        return entry.content
    }

    func store(_ content: CompetitionDetailContent, for key: String) {
        loadFromDiskIfNeeded()
        entriesByKey[key] = CacheEntry(content: content, cachedAt: Date())
        if entriesByKey.count > maximumEntryCount {
            let keysToRemove = entriesByKey
                .sorted { $0.value.cachedAt < $1.value.cachedAt }
                .prefix(entriesByKey.count - maximumEntryCount)
                .map(\.key)
            keysToRemove.forEach { entriesByKey[$0] = nil }
        }
        persistToDisk()
    }

    func clear() {
        entriesByKey.removeAll()
        hasLoadedFromDisk = true
        try? FileManager.default.removeItem(at: cacheFileURL())
        try? FileManager.default.removeItem(at: legacyCacheFileURL())
    }
}

private actor CompetitionScheduleParseStore {
    static let shared = CompetitionScheduleParseStore()

    private var scheduleDaysByKey: [String: [CompetitionScheduleDay]] = [:]

    func scheduleDays(
        for key: String,
        forceRefresh: Bool,
        parser: @escaping @Sendable () async -> [CompetitionScheduleDay]
    ) async -> [CompetitionScheduleDay] {
        if !forceRefresh, let cached = scheduleDaysByKey[key] {
            return cached
        }

        let parsed = await parser()
        scheduleDaysByKey[key] = parsed
        return parsed
    }

    func clear() {
        scheduleDaysByKey.removeAll()
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

    func clear() {
        cachedCountries = nil
        hasLoadedFromDisk = false
        try? FileManager.default.removeItem(at: cacheFileURL())
    }
}

private actor CompetitionLocalizedNameStore {
    static let shared = CompetitionLocalizedNameStore()

    private var cachedLocalizedNames: [String: LocalizedCompetitionInfo]?
    private var loadingTask: Task<[String: LocalizedCompetitionInfo], Never>?
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

        if let loadingTask {
            return await loadingTask.value
        }

        let task = Task {
            await loader()
        }
        loadingTask = task
        let loaded = await task.value
        loadingTask = nil

        if !loaded.isEmpty {
            cachedLocalizedNames = loaded
            saveToDisk(loaded)
        }
        return loaded
    }

    func merge(_ localizedNames: [String: LocalizedCompetitionInfo]) {
        guard !localizedNames.isEmpty else { return }
        loadFromDiskIfNeeded()
        var merged = cachedLocalizedNames ?? [:]
        merged.merge(localizedNames) { _, new in new }
        cachedLocalizedNames = merged
        saveToDisk(merged)
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

    func clear() {
        cachedLocalizedNames = nil
        loadingTask = nil
        hasLoadedFromDisk = false
        try? FileManager.default.removeItem(at: cacheFileURL())
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

    func clear() {
        inMemorySnapshots.removeAll()
        hasLoadedFromDisk = false
        try? FileManager.default.removeItem(at: cacheFileURL())
    }
}


private actor CompetitionRegistrationSummaryStore {
    static let shared = CompetitionRegistrationSummaryStore()

    private var summariesByCompetitionID: [String: CompetitionRegistrationSummary] = [:]

    func summary(for competitionID: String) -> CompetitionRegistrationSummary? {
        summariesByCompetitionID[competitionID]
    }

    func store(_ summary: CompetitionRegistrationSummary, for competitionID: String) {
        summariesByCompetitionID[competitionID] = summary
    }

    func clear() {
        summariesByCompetitionID.removeAll()
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

    func clear() {
        previewsByKey.removeAll()
        hasLoadedFromDisk = false
        try? FileManager.default.removeItem(at: cacheFileURL())
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

nonisolated private let southAmericaCountryCodes: Set<String> = [
    "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PE", "PY", "SR", "UY", "VE"
]

nonisolated private let northAmericaCountryCodes: Set<String> = [
    "AG", "AI", "AW", "BB", "BL", "BM", "BQ", "BS", "BZ", "CA", "CR", "CU", "CW", "DM",
    "DO", "GD", "GL", "GP", "GT", "HN", "HT", "JM", "KN", "KY", "LC", "MF", "MQ", "MS",
    "MX", "NI", "PA", "PM", "PR", "SV", "SX", "TC", "TT", "US", "VC", "VG", "VI"
]

nonisolated private let europeCountryCodes: Set<String> = [
    "AD", "AL", "AT", "AX", "BA", "BE", "BG", "BY", "CH", "CY", "CZ", "DE", "DK", "EE",
    "ES", "FI", "FO", "FR", "GB", "GG", "GI", "GR", "HR", "HU", "IE", "IM", "IS", "IT",
    "JE", "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "MT", "NL", "NO", "PL", "PT",
    "RO", "RS", "RU", "SE", "SI", "SJ", "SK", "SM", "UA", "VA", "XK"
]

nonisolated private let asiaCountryCodes: Set<String> = [
    "AE", "AF", "AM", "AZ", "BD", "BH", "BN", "BT", "CN", "GE", "HK", "ID", "IL", "IN",
    "IQ", "IR", "JO", "JP", "KG", "KH", "KP", "KR", "KW", "KZ", "LA", "LB", "LK", "MM",
    "MN", "MO", "MV", "MY", "NP", "OM", "PH", "PK", "PS", "QA", "SA", "SG", "SY", "TH",
    "TJ", "TM", "TR", "TW", "UZ", "VN", "YE"
]

nonisolated private let africaCountryCodes: Set<String> = [
    "AO", "BF", "BI", "BJ", "BW", "CD", "CF", "CG", "CI", "CM", "CV", "DJ", "DZ", "EG",
    "EH", "ER", "ET", "GA", "GH", "GM", "GN", "GQ", "GW", "KE", "KM", "LR", "LS", "LY",
    "MA", "MG", "ML", "MR", "MU", "MW", "MZ", "NA", "NE", "NG", "RW", "SC", "SD", "SL",
    "SN", "SO", "SS", "ST", "SZ", "TD", "TG", "TN", "TZ", "UG", "ZA", "ZM", "ZW"
]

nonisolated private let oceaniaCountryCodes: Set<String> = [
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

nonisolated private final class CompetitionPayloadDateParser: @unchecked Sendable {
    private let iso8601WithFractionalSeconds: ISO8601DateFormatter
    private let iso8601: ISO8601DateFormatter
    private let dateOnly: DateFormatter

    nonisolated init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso8601WithFractionalSeconds = fractional

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        iso8601 = standard

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        dateOnly = day
    }

    nonisolated func date(from value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value)
            ?? iso8601.date(from: value)
            ?? dateOnly.date(from: value)
    }
}

private struct WCACompetitionPayload: Decodable, Sendable {
    let id: String
    let name: String
    let shortName: String?
    let shortDisplayName: String?
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
    let championshipTypes: [String]?

    nonisolated var summary: CompetitionSummary {
        CompetitionSummary(
            id: id,
            name: name,
            shortDisplayName: shortDisplayName ?? shortName,
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
            championshipTypes: championshipTypes,
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
    let pageSize: Int
}

private struct WCARegistrationStatusPayload: Decodable {
    let id: String
    let registrationStatus: WCACompetitionRegistrationStatus

    private enum CodingKeys: String, CodingKey {
        case id
        case registrationStatus = "registration_status"
    }
}

private struct StoredCompetitionCacheSnapshot: Codable {
    let competitions: [CompetitionSummary]
    let totalCount: Int?
    let lastUpdated: Date
}

private struct WCAScheduleProps: Decodable {
    let wcifSchedule: WCASchedule
}

private struct WCAEventsProps: Decodable {
    struct CompetitionInfo: Decodable {
        let usesCutoff: Bool
        let usesQualification: Bool

        private enum CodingKeys: String, CodingKey {
            case usesCutoff = "uses_cutoff?"
            case usesQualification = "uses_qualification?"
        }
    }

    let wcifEvents: [WCAEventPayload]
    let competitionInfo: CompetitionInfo?
}

private struct WCAEventPayload: Decodable {
    struct Qualification: Decodable {
        let whenDate: String
        let type: String
        let resultType: String
        let level: Int?
    }

    struct Round: Decodable {
        struct TimeLimit: Decodable {
            let centiseconds: Int
            let cumulativeRoundIds: [String]
        }

        struct Cutoff: Decodable {
            let numberOfAttempts: Int
            let attemptResult: Int

            private enum CodingKeys: String, CodingKey {
                case numberOfAttempts
                case attemptResult
                case resultValue
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                numberOfAttempts = try container.decode(Int.self, forKey: .numberOfAttempts)
                attemptResult = try container.decodeIfPresent(Int.self, forKey: .attemptResult)
                    ?? container.decode(Int.self, forKey: .resultValue)
            }
        }

        struct AdvancementCondition: Decodable {
            let type: String
            let level: Int
        }

        struct ParticipationRuleset: Decodable {
            struct ParticipationSource: Decodable {
                struct ResultCondition: Decodable {
                    let type: String
                    let scope: String?
                    let value: Int
                }

                let type: String
                let resultCondition: ResultCondition?
            }

            let participationSource: ParticipationSource
        }

        let id: String
        let format: String
        let timeLimit: TimeLimit?
        let cutoff: Cutoff?
        let advancementCondition: AdvancementCondition?
        let participationRuleset: ParticipationRuleset?
    }

    let id: String
    let rounds: [Round]
    let qualification: Qualification?
}

private struct WCASchedule: Decodable {
    let venues: [WCAVenue]
}

private struct WCAVenue: Decodable {
    let id: Int
    let name: String
    let timezone: String
    let rooms: [WCARoom]
}

private struct WCARoom: Decodable {
    let id: Int
    let name: String
    let color: String?
    let activities: [WCAActivity]
}

private struct WCAActivity: Decodable {
    let id: Int
    let name: String
    let activityCode: String
    let startTime: Date
    let endTime: Date
    let childActivities: [WCAActivity]
}
