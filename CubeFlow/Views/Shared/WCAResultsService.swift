import Foundation

struct WCAPersonResultsPage: Sendable, Codable {
    let contentLanguage: String
    let summary: WCAPersonResultsSummary
    let personalRecords: [WCAPersonalRecord]
    let resultsSections: [WCAEventResultsSection]
}

struct WCAPersonResultsSummary: Sendable, Codable {
    let region: String
    let wcaId: String
    let gender: String
    let competitions: String
    let completedSolves: String
}

struct WCAEventDescriptor: Identifiable, Hashable, Sendable, Codable {
    let code: String
    let name: String

    var id: String { code }

    private var shortLabelLocalizationKey: String? {
        switch code {
        case "333": return "wca.event.short.3x3"
        case "222": return "wca.event.short.2x2"
        case "444": return "wca.event.short.4x4"
        case "555": return "wca.event.short.5x5"
        case "666": return "wca.event.short.6x6"
        case "777": return "wca.event.short.7x7"
        case "333oh": return "wca.event.short.oh"
        case "clock": return "wca.event.short.clock"
        case "minx": return "wca.event.short.megaminx"
        case "pyram": return "wca.event.short.pyraminx"
        case "skewb": return "wca.event.short.skewb"
        case "sq1": return "wca.event.short.square1"
        default: return nil
        }
    }

    var shortLabel: String {
        guard let key = shortLabelLocalizationKey else {
            return name
        }
        return Bundle.main.localizedString(forKey: key, value: name, table: nil)
    }

    func localizedShortLabel(languageCode: String) -> String {
        guard let key = shortLabelLocalizationKey else {
            return name
        }
        return appLocalizedString(key, languageCode: languageCode, defaultValue: name)
    }
}

struct WCAPersonalRecord: Identifiable, Hashable, Sendable, Codable {
    let event: WCAEventDescriptor
    let singleNationalRank: String?
    let singleContinentRank: String?
    let singleWorldRank: String?
    let single: String?
    let average: String?
    let averageWorldRank: String?
    let averageContinentRank: String?
    let averageNationalRank: String?

    var id: String { event.code }
}

struct WCACompetitionResult: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let competitionName: String
    let competitionPath: String?
    let countryISO2: String?
    let roundName: String
    let place: String?
    let single: String?
    let average: String?
    let solves: [WCAAttemptResult]
}

struct WCAAttemptResult: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let value: String
    let isTrimmed: Bool
}

struct WCAEventResultsSection: Identifiable, Hashable, Sendable, Codable {
    let event: WCAEventDescriptor
    let results: [WCACompetitionResult]

    var id: String { event.code }
}

enum WCAResultsFetchError: LocalizedError {
    case missingWCAID
    case invalidPersonURL
    case requestFailed
    case invalidHTML

    var errorDescription: String? {
        switch self {
        case .missingWCAID:
            return currentAppLocalizedString("wca.results_error_missing_wca_id")
        case .invalidPersonURL:
            return currentAppLocalizedString("wca.results_error_invalid_url")
        case .requestFailed:
            return currentAppLocalizedString("wca.results_error_request_failed")
        case .invalidHTML:
            return currentAppLocalizedString("wca.results_error_invalid_html")
        }
    }
}

enum WCAResultsService {
    struct CachedPersonResultsSnapshot: Sendable {
        let page: WCAPersonResultsPage
        let lastUpdated: Date
    }

    static func fetchPersonResults(
        wcaId: String,
        appLanguageCode: String,
        useCache: Bool = true
    ) async throws -> WCAPersonResultsPage {
        let trimmedWCAID = wcaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWCAID.isEmpty else {
            throw WCAResultsFetchError.missingWCAID
        }

        let cacheKey = personResultsCacheKey(wcaId: trimmedWCAID, languageCode: appLanguageCode)
        if useCache, let cachedSnapshot = await WCAResultsPageCacheStore.shared.snapshot(for: cacheKey) {
            return cachedSnapshot.page
        }

        guard let url = URL(string: "https://www.worldcubeassociation.org/persons/\(trimmedWCAID)") else {
            throw WCAResultsFetchError.invalidPersonURL
        }

        var request = URLRequest(url: url)
        request.setValue(acceptLanguageHeader(for: appLanguageCode), forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            throw WCAResultsFetchError.requestFailed
        }

        let parsedPage = try WCAResultsHTMLParser.parse(html: html, requestedLanguageCode: appLanguageCode)
        await WCAResultsPageCacheStore.shared.store(parsedPage, for: cacheKey, lastUpdated: Date())
        return parsedPage
    }

    static func cachedPersonResults(
        wcaId: String,
        appLanguageCode: String
    ) async -> CachedPersonResultsSnapshot? {
        let trimmedWCAID = wcaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWCAID.isEmpty else { return nil }

        let cacheKey = personResultsCacheKey(wcaId: trimmedWCAID, languageCode: appLanguageCode)
        guard let snapshot = await WCAResultsPageCacheStore.shared.snapshot(for: cacheKey) else { return nil }
        return CachedPersonResultsSnapshot(page: snapshot.page, lastUpdated: snapshot.lastUpdated)
    }

    static func enrichPersonResults(
        _ page: WCAPersonResultsPage,
        appLanguageCode: String
    ) async -> WCAPersonResultsPage {
        await localizedCompetitionNamesIfNeeded(for: page, appLanguageCode: appLanguageCode)
    }

    private static func acceptLanguageHeader(for appLanguageCode: String) -> String {
        appAcceptLanguageHeader(for: appLanguageCode)
    }

    private static func personResultsCacheKey(wcaId: String, languageCode: String) -> String {
        "\(wcaId)|\(languageCode)"
    }

    private static func localizedCompetitionNamesIfNeeded(
        for page: WCAPersonResultsPage,
        appLanguageCode: String
    ) async -> WCAPersonResultsPage {
        let competitionIDs = Set(
            page.resultsSections
                .flatMap(\.results)
                .compactMap { competitionIdentifier(from: $0.competitionPath) }
        )
        let countryCodesByCompetition = await WCAResultsSupplementalStore.shared.countryCodes(
            for: competitionIDs
        ) { ids in
            await fetchCompetitionCountryCodes(for: ids)
        }
        let localizedNames = cubingLanguageCode(for: appLanguageCode) == "zh_cn"
            ? await WCAResultsSupplementalStore.shared.localizedCompetitionNames {
                await fetchCompetitionNameMapFromCubing()
            }
            : [:]

        let mappedSections = page.resultsSections.map { section in
            WCAEventResultsSection(
                event: section.event,
                results: section.results.map { result in
                    let localizedName =
                        result.competitionPath.flatMap { localizedNames[normalizeCompetitionLookupKey($0)] } ??
                        localizedNames[normalizeCompetitionLookupKey(result.competitionName)]
                    return WCACompetitionResult(
                        id: result.id,
                        competitionName: localizedName ?? result.competitionName,
                        competitionPath: result.competitionPath,
                        countryISO2: result.competitionPath.flatMap {
                            competitionIdentifier(from: $0).flatMap { countryCodesByCompetition[$0] }
                        },
                        roundName: result.roundName,
                        place: result.place,
                        single: result.single,
                        average: result.average,
                        solves: result.solves
                    )
                }
            )
        }

        return WCAPersonResultsPage(
            contentLanguage: page.contentLanguage,
            summary: page.summary,
            personalRecords: page.personalRecords,
            resultsSections: mappedSections
        )
    }

    private static func fetchCompetitionCountryCodes(for competitionIDs: Set<String>) async -> [String: String] {
        guard !competitionIDs.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, String?).self, returning: [String: String].self) { group in
            for competitionID in competitionIDs {
                group.addTask {
                    (competitionID, await fetchCompetitionCountryCode(for: competitionID))
                }
            }

            var lookup: [String: String] = [:]
            for await (competitionID, countryCode) in group {
                if let countryCode {
                    lookup[competitionID] = countryCode
                }
            }
            return lookup
        }
    }

    private static func fetchCompetitionCountryCode(for competitionID: String) async -> String? {
        guard let encodedID = competitionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.worldcubeassociation.org/api/v0/competitions/\(encodedID)") else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let competition = try? decoder.decode(WCACompetitionCountryPayload.self, from: data) else {
            return nil
        }

        return competition.countryIso2
    }

    private static func competitionIdentifier(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }

        let canonical = value
            .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competitions/"#, with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? value
        let trimmed = canonical.components(separatedBy: "?").first ?? canonical
        let fragmentTrimmed = trimmed.components(separatedBy: "#").first ?? trimmed
        let cleaned = fragmentTrimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    fileprivate static func normalizeCompetitionLookupKey(_ value: String) -> String {
        let canonical = value
            .replacingOccurrences(of: #"^https?://www\.worldcubeassociation\.org/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competitions/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^https?://cubing\.com/competition/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^/competition/"#, with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? value
        let trimmed = canonical
            .components(separatedBy: "?").first ?? canonical
        let fragmentTrimmed = trimmed
            .components(separatedBy: "#").first ?? trimmed
        return fragmentTrimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func fetchCompetitionNameMapFromCubing() async -> [String: String] {
        guard let url = URL(string: "https://cubing.com/competition?year=&type=WCA&province=&event=") else { return [:] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN, zh-Hans;q=0.95, zh;q=0.9, en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return [:]
        }
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let matches = WCAResultsHTMLParser.captures(
            in: html,
            pattern: #"<a[^>]*class="comp-type-wca"[^>]*href="(?:https://cubing\.com)?/competition/([^"]+)"[^>]*>(.*?)</a>"#
        )

        var lookup: [String: String] = [:]
        for groups in matches {
            guard groups.count >= 2 else { continue }
            let slug = groups[0]
            let anchorHTML = groups[1]
            let chineseName = WCAResultsHTMLParser.cleanHTML(anchorHTML)
            guard !chineseName.isEmpty else { continue }
            lookup[WCAResultsService.normalizeCompetitionLookupKey(slug)] = chineseName
        }
        return lookup
    }
}

private struct WCACompetitionCountryPayload: Decodable {
    let id: String
    let countryIso2: String
}

private actor WCAResultsSupplementalStore {
    static let shared = WCAResultsSupplementalStore()

    private var cachedCompetitionCountryCodes: [String: String] = [:]
    private var cachedLocalizedCompetitionNames: [String: String]?

    func countryCodes(
        for competitionIDs: Set<String>,
        loader: @escaping (Set<String>) async -> [String: String]
    ) async -> [String: String] {
        let missingIDs = competitionIDs.filter { cachedCompetitionCountryCodes[$0] == nil }
        if !missingIDs.isEmpty {
            let loaded = await loader(missingIDs)
            for (competitionID, countryCode) in loaded {
                cachedCompetitionCountryCodes[competitionID] = countryCode
            }
        }

        return competitionIDs.reduce(into: [:]) { partialResult, competitionID in
            if let countryCode = cachedCompetitionCountryCodes[competitionID] {
                partialResult[competitionID] = countryCode
            }
        }
    }

    func localizedCompetitionNames(
        loader: @escaping () async -> [String: String]
    ) async -> [String: String] {
        if let cachedLocalizedCompetitionNames {
            return cachedLocalizedCompetitionNames
        }

        let loaded = await loader()
        cachedLocalizedCompetitionNames = loaded
        return loaded
    }
}

private actor WCAResultsPageCacheStore {
    static let shared = WCAResultsPageCacheStore()

    private var inMemorySnapshots: [String: StoredWCAResultsPageSnapshot] = [:]
    private var hasLoadedFromDisk = false

    func snapshot(for key: String) -> StoredWCAResultsPageSnapshot? {
        loadFromDiskIfNeeded()
        return inMemorySnapshots[key]
    }

    func store(_ page: WCAPersonResultsPage, for key: String, lastUpdated: Date) {
        loadFromDiskIfNeeded()
        inMemorySnapshots[key] = StoredWCAResultsPageSnapshot(page: page, lastUpdated: lastUpdated)
        saveToDisk()
    }

    private func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory
            .appendingPathComponent("CubeFlow", isDirectory: true)
            .appendingPathComponent("wca-person-results-cache-v1.json")
    }

    private func loadFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        hasLoadedFromDisk = true

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: cacheFileURL()),
              let stored = try? decoder.decode([String: StoredWCAResultsPageSnapshot].self, from: data) else {
            return
        }

        inMemorySnapshots = stored
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(inMemorySnapshots) else { return }
        let fileURL = cacheFileURL()
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}

private struct StoredWCAResultsPageSnapshot: Codable, Sendable {
    let page: WCAPersonResultsPage
    let lastUpdated: Date
}

private enum WCAResultsHTMLParser {
    nonisolated static func parse(html: String, requestedLanguageCode: String) throws -> WCAPersonResultsPage {
        let summary = try parseSummary(from: html)
        let personalRecords = try parsePersonalRecords(from: html)
        let resultsSections = try parseResultsSections(from: html)
        return WCAPersonResultsPage(
            contentLanguage: requestedLanguageCode,
            summary: summary,
            personalRecords: personalRecords,
            resultsSections: resultsSections
        )
    }

    private nonisolated static func parseSummary(from html: String) throws -> WCAPersonResultsSummary {
        guard let tbodyHTML = firstCapture(
            in: html,
            pattern: #"<div class="details">.*?<tbody>(.*?)</tbody>.*?</table>"#
        ) else {
            throw WCAResultsFetchError.invalidHTML
        }

        let values = captures(in: tbodyHTML, pattern: #"<td[^>]*>(.*?)</td>"#)
            .compactMap { $0.first }
            .map(cleanHTML)

        guard values.count >= 5 else {
            throw WCAResultsFetchError.invalidHTML
        }

        return WCAPersonResultsSummary(
            region: values[0],
            wcaId: values[1],
            gender: values[2],
            competitions: values[3],
            completedSolves: values[4]
        )
    }

    private nonisolated static func parsePersonalRecords(from html: String) throws -> [WCAPersonalRecord] {
        guard let tbodyHTML = firstCapture(
            in: html,
            pattern: #"<div class="personal-records">.*?<tbody>(.*?)</tbody>"#
        ) else {
            throw WCAResultsFetchError.invalidHTML
        }

        return captures(in: tbodyHTML, pattern: #"<tr>(.*?)</tr>"#)
            .compactMap { $0.first }
            .compactMap(parsePersonalRecordRow)
    }

    private nonisolated static func parsePersonalRecordRow(_ rowHTML: String) -> WCAPersonalRecord? {
        guard let eventCode = firstCapture(in: rowHTML, pattern: #"data-event="([^"]+)""#) else {
            return nil
        }

        let cells = captures(in: rowHTML, pattern: #"<td[^>]*>(.*?)</td>"#)
            .compactMap { $0.first }
            .map(cleanHTML)

        guard cells.count >= 9 else {
            return nil
        }

        return WCAPersonalRecord(
            event: WCAEventDescriptor(code: eventCode, name: cells[0]),
            singleNationalRank: emptyToNil(cells[1]),
            singleContinentRank: emptyToNil(cells[2]),
            singleWorldRank: emptyToNil(cells[3]),
            single: emptyToNil(cells[4]),
            average: emptyToNil(cells[5]),
            averageWorldRank: emptyToNil(cells[6]),
            averageContinentRank: emptyToNil(cells[7]),
            averageNationalRank: emptyToNil(cells[8])
        )
    }

    private nonisolated static func parseResultsSections(from html: String) throws -> [WCAEventResultsSection] {
        let bodyMatches = captures(
            in: html,
            pattern: #"<tbody class="event-([^"]+)">(.*?)</tbody>"#
        )

        guard !bodyMatches.isEmpty else {
            throw WCAResultsFetchError.invalidHTML
        }

        return bodyMatches.compactMap { groups in
            guard groups.count >= 2 else { return nil }
            let eventCode = groups[0]
            let bodyHTML = groups[1]
            return parseEventResultsSection(eventCode: eventCode, bodyHTML: bodyHTML)
        }
    }

    private nonisolated static func parseEventResultsSection(eventCode: String, bodyHTML: String) -> WCAEventResultsSection? {
        let eventName = firstCapture(
            in: bodyHTML,
            pattern: #"<td colspan="12" class="event">.*?</i>\s*(.*?)\s*</td>"#
        ).map(cleanHTML) ?? eventCode

        let rowHTMLs = captures(in: bodyHTML, pattern: #"<tr class="result[^"]*">(.*?)</tr>"#)
            .compactMap { $0.first }

        var currentCompetitionName: String?
        var currentCompetitionPath: String?

        let results = rowHTMLs.enumerated().compactMap { index, rowHTML -> WCACompetitionResult? in
            let cells = captures(in: rowHTML, pattern: #"<td class="([^"]*)"[^>]*>(.*?)</td>"#)
            guard cells.count >= 7 else { return nil }

            let competitionCellHTML = cells[0].count > 1 ? cells[0][1] : ""
            let competitionNameCandidate = cleanHTML(competitionCellHTML)
            let competitionPathCandidate = firstCapture(in: competitionCellHTML, pattern: #"href="([^"]+)""#)

            if let competitionName = emptyToNil(competitionNameCandidate) {
                currentCompetitionName = competitionName
                currentCompetitionPath = competitionPathCandidate
            }

            guard let resolvedCompetitionName = currentCompetitionName else {
                return nil
            }

            let values = cells.map { groups in
                cleanHTML(groups.count > 1 ? groups[1] : "")
            }

            let solveCells = Array(cells.dropFirst(7))
            let solveValues = solveCells.enumerated().compactMap { solveIndex, groups -> WCAAttemptResult? in
                let className = groups.first ?? ""
                let value = cleanHTML(groups.count > 1 ? groups[1] : "")
                guard !value.isEmpty else { return nil }
                return WCAAttemptResult(
                    id: "\(eventCode)-\(index)-solve-\(solveIndex)",
                    value: value,
                    isTrimmed: className.contains("trimmed")
                )
            }
            let roundName = values.count > 1 ? values[1] : ""
            let place = values.count > 2 ? emptyToNil(values[2]) : nil
            let single = values.count > 3 ? emptyToNil(values[3]) : nil
            let average = values.count > 5 ? emptyToNil(values[5]) : nil

            return WCACompetitionResult(
                id: "\(eventCode)-\(index)-\(resolvedCompetitionName)-\(values[1])",
                competitionName: resolvedCompetitionName,
                competitionPath: currentCompetitionPath,
                countryISO2: nil,
                roundName: roundName,
                place: place,
                single: single,
                average: average,
                solves: solveValues
            )
        }

        guard !results.isEmpty else { return nil }
        return WCAEventResultsSection(
            event: WCAEventDescriptor(code: eventCode, name: eventName),
            results: results
        )
    }

    fileprivate nonisolated static func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsRange).map { match in
            (1 ..< match.numberOfRanges).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    private nonisolated static func firstCapture(in text: String, pattern: String) -> String? {
        captures(in: text, pattern: pattern).first?.first
    }

    fileprivate nonisolated static func cleanHTML(_ html: String) -> String {
        var cleaned = html
        cleaned = cleaned.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        cleaned = decodeHTMLEntities(in: cleaned)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func decodeHTMLEntities(in text: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&lt;", "<"),
            ("&gt;", ">")
        ]

        return entities.reduce(text) { partialResult, entity in
            partialResult.replacingOccurrences(of: entity.0, with: entity.1)
        }
    }

    private nonisolated static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
