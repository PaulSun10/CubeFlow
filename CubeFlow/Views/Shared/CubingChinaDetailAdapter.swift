import Foundation

/// Reads public SSR state, never executing page scripts or relying on Nuxt table indices.
nonisolated struct CubingChinaPageState {
    private let table: [Any]

    init?(html: String) {
        guard let payload = CubingChinaSemanticHTML.firstCapture(html,
            pattern: #"(?is)<script\b[^>]*\bid=["']__NUXT_DATA__["'][^>]*>(.*?)</script>"#),
              payload.utf8.count < 12_000_000, let data = payload.data(using: .utf8),
              let table = try? JSONSerialization.jsonObject(with: data) as? [Any],
              table.count < 100_000 else { return nil }
        self.table = table
    }

    func objects(containing key: String) -> [[String: Any]] {
        var cache: [Int: Any] = [:]
        var budget = 500_000
        var ancestors: Set<Int> = []
        return table.indices.compactMap { index in
            guard let object = table[index] as? [String: Any], object[key] != nil else { return nil }
            return resolve(index, ancestors: &ancestors, cache: &cache, budget: &budget) as? [String: Any]
        }
    }

    func scalarStrings(containing key: String, fields: [String]) -> [[String: String]] {
        table.compactMap { item in
            guard let object = item as? [String: Int], object[key] != nil else { return nil }
            return Dictionary(uniqueKeysWithValues: fields.compactMap { field in
                guard let index = object[field], table.indices.contains(index),
                      let value = table[index] as? String, !value.isEmpty else { return nil }
                return (field, value)
            })
        }
    }

    private func resolve(_ index: Int, ancestors: inout Set<Int>, cache: inout [Int: Any], budget: inout Int) -> Any? {
        guard table.indices.contains(index), !ancestors.contains(index), budget > 0, ancestors.count < 80 else { return nil }
        if let value = cache[index] { return value }
        budget -= 1
        ancestors.insert(index)
        defer { ancestors.remove(index) }
        let value: Any
        if let object = table[index] as? [String: Int] {
            value = object.mapValues { resolve($0, ancestors: &ancestors, cache: &cache, budget: &budget) ?? NSNull() }
        } else if let array = table[index] as? [Any] {
            if let reducer = array.first as? String {
                // Only observed serialization wrappers are unwrapped. Unknown reducers fail closed.
                guard ["Reactive", "ShallowReactive", "Ref", "ShallowRef"].contains(reducer),
                      array.count == 2, let target = array[1] as? Int else { return nil }
                return resolve(target, ancestors: &ancestors, cache: &cache, budget: &budget)
            }
            value = array.map { item -> Any in
                guard let target = item as? Int else { return NSNull() }
                return resolve(target, ancestors: &ancestors, cache: &cache, budget: &budget) ?? NSNull()
            }
        } else {
            value = table[index]
        }
        cache[index] = value
        return value
    }
}

nonisolated enum CubingChinaDetailSection: String {
    case about, regulations, travel, registration
}

nonisolated struct CubingChinaSectionParse {
    let blocks: [CompetitionDetailTextBlock]
    let source: String
    let nonemptyContentFailed: Bool
}

nonisolated enum CubingChinaDetailAdapter {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static func competition(in html: String) -> [String: Any]? {
        CubingChinaPageState(html: html)?.objects(containing: "wcaCompetitionId").first
    }

    static func wcaID(in html: String) -> String? {
        wcaID(in: competition(in: html))
    }

    static func wcaID(in metadata: [String: Any]?) -> String? {
        guard let id = metadata?["wcaCompetitionId"] as? String,
              PublishedCompetitionService.validCompetitionID(id) else { return nil }
        return id
    }

    static func sharingArtwork(in html: String) -> CompetitionSharingArtwork? {
        sharingArtwork(in: competition(in: html))
    }

    static func sharingArtwork(in metadata: [String: Any]?) -> CompetitionSharingArtwork? {
        guard let metadata else { return nil }
        for (field, kind) in [("banner", CompetitionSharingArtwork.Kind.banner), ("logo", .logo)] {
            let raw = metadata[field] as? String ?? (metadata[field] as? [String: Any])?["url"] as? String
            guard let raw, raw.hasPrefix("https://") || raw.hasPrefix("/"),
                  let url = URL(string: raw, relativeTo: URL(string: "https://cubing.com"))?.absoluteURL,
                  url.scheme == "https", url.host != nil else { continue }
            return .init(kind: kind, url: url)
        }
        return nil
    }

    static func sharingLocation(in metadata: [String: Any]?, language: String) -> String? {
        guard language.hasPrefix("zh"), let locations = metadata?["locations"] as? [[String: Any]],
              !locations.isEmpty else { return nil }
        var places: Set<String> = []
        for location in locations {
            guard location["regionIso2"] as? String == "CN" else { return nil }
            let values = [location["cityName"], location["provinceName"]].compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { CompetitionNameScript.display($0, language: language) }
            guard !values.isEmpty else { return nil }
            places.insert((values.first == values.last ? Array(values.prefix(1)) : values).joined(separator: "\u{FF0C}"))
        }
        guard places.count == 1, let place = places.first else { return nil }
        // A report labels the country, not the browser's mainland region filter.
        let country = CompetitionNameScript.display("\u{4E2D}\u{56FD}", language: language)
        return place + " \u{00B7} " + country
    }

    static func blocks(html: String, section: CubingChinaDetailSection, language: String) -> CubingChinaSectionParse {
        let start = ProcessInfo.processInfo.systemUptime
        defer { CompetitionLoadingTrace.record("china-section-parse", since: start, detail: section.rawValue) }
        let key: String
        switch section {
        case .about: key = "information"
        case .regulations: key = "regulations"
        case .travel: key = "travel"
        case .registration: key = "registration"
        }
        let clean = CubingChinaSemanticHTML.sanitize(html)
        let sections = CubingChinaSemanticHTML.elements("section", in: clean)
        var hasOrganizer = false
        let rendered = sections.enumerated().flatMap { index, content -> [CompetitionDetailTextBlock] in
            guard let heading = CubingChinaSemanticHTML.firstCapture(content,
                pattern: #"(?is)<h[23]\b[^>]*>(.*?)</h[23]>"#) else { return [] }
            let title = CubingChinaSemanticHTML.text(heading)
            let body = content.replacingOccurrences(of: #"(?is)^.*?<h[23]\b[^>]*>.*?</h[23]>"#, with: "", options: .regularExpression)
            let organizer = body.contains("prose") ? CubingChinaSemanticHTML.elements("div", in: body, includesTags: true) { opening in
                opening.contains("prose") && CubingChinaSemanticHTML.firstCapture(opening,
                    pattern: #"(?i)\bclass\s*=\s*["']([^"']*)["']"#)?
                        .split(whereSeparator: \.isWhitespace).contains("prose") == true
            } : []
            let id = "cubing-v2-\(section.rawValue)-\(index)"
            var blocks: [CompetitionDetailTextBlock] = []
            func append(_ fragment: String, id: String) {
                let plain = CubingChinaSemanticHTML.text(fragment)
                guard !plain.isEmpty || fragment.contains("<img") else { return }
                blocks.append(CompetitionDetailTextBlock(id: id, title: blocks.isEmpty ? title : nil, body: plain, html: fragment))
            }
            var tail = body[...]
            for (part, document) in organizer.enumerated() {
                guard let range = tail.range(of: document) else { continue }
                append(String(tail[..<range.lowerBound]), id: part == 0 ? id : "\(id)-before-\(part)")
                let count = blocks.count
                append(document, id: "cubing-v2-organizer-\(key)-\(index)\(part == 0 ? "" : "-\(part)")")
                if blocks.count != count { hasOrganizer = true }
                tail = tail[range.upperBound...]
            }
            append(String(tail), id: organizer.isEmpty ? id : "\(id)-after")
            return blocks
        }
        if hasOrganizer {
            // SSR already has the localized organizer document and its place
            // in the page. Avoid decoding all Nuxt state to find a duplicate.
            return CubingChinaSectionParse(blocks: rendered, source: "semantic-sections+organizer-prose", nonemptyContentFailed: false)
        }
        let attributes = competition(in: html)?["i18nAttributes"] as? [[String: Any]] ?? []
        let matching = attributes.filter { $0["key"] as? String == key }
        let locale = language.hasPrefix("zh") ? "zh" : "en"
        if let attribute = matching.first(where: { $0["locale"] as? String == locale }) ?? matching.first,
           let rich = attribute["value"] as? String, !rich.isEmpty {
            let blocks = CubingChinaSemanticHTML.headingBlocks(rich, prefix: "cubing-v2-\(key)")
            if !rendered.isEmpty {
                // A nonempty automatic Venue section is not proof the organizer document was captured.
                let text = normalizedDocumentText(rendered.map { ($0.title ?? "") + " " + $0.body }.joined(separator: " "))
                let renderedHTML = rendered.compactMap(\.html).joined()
                let missing = blocks.filter { block in
                    let body = normalizedDocumentText(block.body)
                    if !body.isEmpty { return !text.contains(body) }
                    return !renderedHTML.contains(block.html ?? "")
                }
                return CubingChinaSectionParse(blocks: section == .travel ? missing + rendered : rendered + missing,
                    source: missing.isEmpty ? "semantic-sections" : "semantic-sections+organizer-content", nonemptyContentFailed: false)
            }
            return CubingChinaSectionParse(blocks: blocks, source: "embedded-organizer-content", nonemptyContentFailed: blocks.isEmpty)
        }
        if !rendered.isEmpty {
            return CubingChinaSectionParse(blocks: rendered, source: "semantic-sections", nonemptyContentFailed: false)
        }
        return CubingChinaSectionParse(blocks: [], source: "legacy-or-unavailable",
            nonemptyContentFailed: CubingChinaPageState(html: html) != nil && !CubingChinaSemanticHTML.text(clean).isEmpty)
    }

    private static func normalizedDocumentText(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    static func mapLocations(html: String, language: String) -> [CompetitionTravelMapLocation] {
        let locations = competition(in: html)?["locations"] as? [[String: Any]] ?? []
        return locations.compactMap { item in
            guard let latitude = item["latitude"] as? Double, let longitude = item["longitude"] as? Double,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            let venue = localized(item, key: "venue", language: language) ?? ""
            return CompetitionTravelMapLocation(id: "cubing-v2-location-\(item["id"] ?? "")", latitude: latitude,
                longitude: longitude, venue: venue, address: venue)
        }
    }

    static func competitors(html: String, language: String) -> [CompetitionCompetitorPreview] {
        let rows = CubingChinaPageState(html: html)?.objects(containing: "registrationEvents") ?? []
        return rows.compactMap { row in
            guard let user = row["user"] as? [String: Any], let name = localized(user, key: "name", language: language),
                  let id = row["id"] as? Int else { return nil }
            let events = row["registrationEvents"] as? [[String: Any]] ?? []
            return CompetitionCompetitorPreview(id: "cubing-registration-\(id)", number: (row["number"] as? Int).map(String.init),
                name: name, gender: user["gender"] as? String, subtitle: user["regionIso2"] as? String,
                registeredEventIDs: events.compactMap { $0["eventId"] as? String },
                wcaID: user["wcaId"] as? String, countryISO2: user["regionIso2"] as? String)
        }
    }

    @MainActor
    static func schedule(html: String, language: String) -> [CompetitionScheduleDay] {
        guard let payload = CubingChinaPageState(html: html)?.objects(containing: "schedule").first,
              let rows = payload["schedule"] as? [[String: Any]] else { return [] }
        let dates = CubingChinaScheduleDates()
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func minutes(_ date: Date) -> Int {
            let values = calendar.dateComponents([.hour, .minute], from: date)
            return (values.hour ?? 0) * 60 + (values.minute ?? 0)
        }
        let entries = rows.compactMap { row -> CompetitionScheduleEntry? in
            guard let startString = row["startTime"] as? String, let endString = row["endTime"] as? String,
                  let start = dates.date(startString), let end = dates.date(endString), end > start,
                  let id = row["id"] as? Int else { return nil }
            let venue = row["venue"] as? [String: Any] ?? [:]
            let round = row["round"] as? [String: Any] ?? [:]
            let eventID = row["eventId"] as? String
            let activity = row["activityType"] as? String
            let title = localized(row, key: "name", language: language)
                ?? eventID.map { CompetitionEventPresentation.localizedFullName(for: $0, languageCode: language) }
                ?? activityTitle(activity, language: language)
            let limit = round["timeLimit"] as? [String: Any]
            let cutoff = round["cutoff"] as? [String: Any]
            let advance = round["advancementCondition"] as? [String: Any]
            return CompetitionScheduleEntry(id: "cubing-v2-activity-\(id)",
                timeText: "\(formatter.string(from: start))\u{2013}\(formatter.string(from: end))", title: title, detailText: nil,
                venueName: localized(venue, key: "name", language: language),
                roomID: (venue["id"] as? Int).map { "cubing-room-\($0)" }, eventCode: eventID,
                group: (row["group"] as? Int).map(String.init),
                round: (round["roundNumber"] as? Int).map(String.init), format: round["format"] as? String,
                cutoff: (cutoff?["attemptResult"] as? Int).map { WCAResultFormatter.string(from: $0, eventID: eventID ?? "333") },
                timeLimit: (limit?["centiseconds"] as? Int).map { WCAResultFormatter.string(from: $0, eventID: eventID ?? "333") },
                advancingCount: (advance?["level"] as? Int).map { "\($0)\((advance?["type"] as? String) == "percent" ? "%" : "")" },
                startTime: start, endTime: end, roomColorHex: venue["color"] as? String,
                startMinuteOfDay: minutes(start), endMinuteOfDay: minutes(end))
        }
        formatter.dateFormat = "yyyy-MM-dd"
        let days = Dictionary(grouping: entries) { formatter.string(from: $0.startTime!) }
        return days.keys.sorted().map { key in
            let items = (days[key] ?? []).sorted { $0.startTime! < $1.startTime! }
            let grouped = Dictionary(grouping: items) { $0.roomID ?? "cubing-room" }
            let venues = grouped.keys.sorted().map { room in
                CompetitionScheduleVenue(id: room, title: grouped[room]?.first?.venueName ?? "", entries: grouped[room] ?? [])
            }
            return CompetitionScheduleDay(id: "cubing-v2-\(key)", title: key, entries: items, venues: venues)
        }
    }

    private static func localized(_ object: [String: Any], key: String, language: String) -> String? {
        let preferred = language.hasPrefix("zh") ? (key == "name" ? "localName" : key + "Zh") : key
        for candidate in [preferred, key + "Zh", key] {
            if let value = object[candidate] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }
    private static func activityTitle(_ activity: String?, language: String) -> String {
        let names = ["checkin": "Check-in", "lunch": "Lunch", "ceremony": "Awards", "award": "Awards", "opening": "Opening", "break": "Break"]
        return appLocalizedString("activity.\(activity ?? "other")", languageCode: language,
            defaultValue: names[activity ?? ""] ?? activity ?? "Activity", tableName: "CompetitionPublished")
    }
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Scoped to one schedule parse. The formatters never cross worker boundaries.
nonisolated struct CubingChinaScheduleDates {
    private let fractional: ISO8601DateFormatter
    private let wholeSeconds = ISO8601DateFormatter()

    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? wholeSeconds.date(from: text)
    }
}

/// Balanced semantic elements tolerate arbitrary presentation wrappers and nested rich content.
nonisolated enum CubingChinaSemanticHTML {
    static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    static func elements(_ tag: String, in html: String, includesTags: Bool = false,
                         matchingOpening: (String) -> Bool = { _ in true }) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)</?\(tag)\\b[^>]*>") else { return [] }
        let string = html as NSString
        var depth = 0, spans: [NSRange] = []
        var root: (start: Int, depth: Int)?
        for match in regex.matches(in: html, range: NSRange(location: 0, length: string.length)) {
            let token = string.substring(with: match.range)
            if token.hasPrefix("</") {
                if let active = root, depth == active.depth {
                    let end = includesTags ? NSMaxRange(match.range) : match.range.location
                    spans.append(NSRange(location: active.start, length: end - active.start))
                    root = nil
                }
                depth = max(0, depth - 1)
            } else {
                depth += 1
                if root == nil, matchingOpening(token) {
                    root = (includesTags ? match.range.location : NSMaxRange(match.range), depth)
                }
            }
        }
        return spans.map { string.substring(with: $0) }
    }
    static func sanitize(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|style|nav|footer)\b.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)\s+on\w+\s*=\s*(["']).*?\1"#, with: "", options: .regularExpression)
    }
    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func headingBlocks(_ html: String, prefix: String) -> [CompetitionDetailTextBlock] {
        let clean = sanitize(html)
        guard !text(clean).isEmpty || clean.contains("<img") else { return [] }
        // Preserve the entire organizer document, including introductory paragraphs before headings.
        return [CompetitionDetailTextBlock(id: prefix, title: nil, body: text(clean), html: clean)]
    }
}
