import XCTest
@testable import CubeFlow

@MainActor final class CompetitionDateWindowTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value.contains("T") ? value : value + "T00:00:00Z")!
    }
    private func window(_ now: String, zone: String = "UTC") -> CompetitionDateWindow {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        return CompetitionDateWindow(now: date(now), calendar: calendar)!
    }
    private func sample(_ id: String, start: String, end: String? = nil) -> CompetitionSummary {
        .init(id: id, name: id, shortDisplayName: nil, startDate: date(start), endDate: date(end ?? start),
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "", venueDetails: nil,
            city: "Fixture", countryISO2: "US", latitude: nil, longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/\(id)", website: nil, dateRange: "Fixture",
            eventIDs: ["333"], championshipTypes: nil, localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }
    private func results(_ rows: [CompetitionSummary], _ status: CompetitionStatusFilter, _ window: CompetitionDateWindow) -> [String] {
        let query = CompetitionQuery(languageCode: "en", region: .all, events: [.threeByThree], year: .all, status: status, dateWindow: window)
        return CompetitionService.filterCompetitions(rows, for: query).map(\.id)
    }
    func testInclusiveRecentWindowAndTodayOverlapUseStartNotEnd() {
        let day = window("2026-10-21T13:00:00Z")
        let rows = [sample("today", start: "2026-10-21", end: "2026-10-23"),
                    sample("day30", start: "2026-09-21"), sample("day31", start: "2026-09-20"),
                    sample("tomorrow", start: "2026-10-22")]
        XCTAssertEqual(Set(results(rows, .recent, day)), ["today", "day30"])
        XCTAssertEqual(Set(results(rows, .present, day)), ["today", "tomorrow"])
        XCTAssertEqual(Set(results(rows, .past, day)), ["day30", "day31"])
    }
    func testMultiDayAndPastEndIsExclusiveOfToday() {
        let day = window("2026-10-21")
        let ongoing = sample("ongoing", start: "2026-10-20", end: "2026-10-22")
        let endsToday = sample("endsToday", start: "2026-10-19", end: "2026-10-21")
        let ended = sample("ended", start: "2026-10-18", end: "2026-10-20")
        XCTAssertFalse(day.contains(ongoing, status: .present))
        XCTAssertTrue(day.contains(ongoing, status: .recent))
        XCTAssertFalse(day.contains(endsToday, status: .past))
        XCTAssertTrue(day.contains(ended, status: .past))
    }
    func testUTCCivilDatesDoNotShiftIntoPreviousDayInWesternTimeZones() {
        let day = window("2026-01-01T03:00:00Z", zone: "America/Los_Angeles")
        XCTAssertEqual(day.isoDay(day.today), "2025-12-31")
        let today = sample("today", start: "2025-12-31")
        XCTAssertTrue(day.contains(today, status: .present))
        XCTAssertTrue(day.contains(today, status: .recent))
        XCTAssertFalse(day.contains(today, status: .past))
        XCTAssertTrue(day.contains(sample("future-year", start: "2099-01-01"), status: .present))
    }
    func testCalendarDaysAcrossDSTMonthAndYearBoundaries() {
        XCTAssertEqual(window("2026-03-08T17:00:00Z", zone: "America/New_York").isoDay(window("2026-03-08T17:00:00Z", zone: "America/New_York").recentStart), "2026-02-06")
        let autumn = window("2026-11-01T18:00:00Z", zone: "America/New_York")
        XCTAssertEqual(autumn.isoDay(autumn.recentStart), "2026-10-02")
        let newYear = window("2026-01-01")
        XCTAssertEqual(newYear.isoDay(newYear.yesterday), "2025-12-31")
        XCTAssertEqual(newYear.isoDay(newYear.recentStart), "2025-12-02")
    }
    func testActualQueryBoundsHaveNoFutureCutoffAndRecentDoesNotUseEndDateUpperBound() {
        let day = window("2026-10-21")
        let present = Dictionary(uniqueKeysWithValues: day.queryItems(status: .present).map { ($0.name, $0.value) })
        let recent = Dictionary(uniqueKeysWithValues: day.queryItems(status: .recent).map { ($0.name, $0.value) })
        let past = Dictionary(uniqueKeysWithValues: day.queryItems(status: .past).map { ($0.name, $0.value) })
        XCTAssertEqual(present["start"], "2026-10-21"); XCTAssertNil(present["end"])
        XCTAssertNil(present["ongoing_and_future"])
        XCTAssertEqual(recent["start"], "2026-09-21"); XCTAssertNil(recent["end"])
        XCTAssertEqual(recent["sort"], "start_date,end_date,name")
        XCTAssertEqual(past["end"], "2026-10-20")
        XCTAssertFalse(day.isAfterToday(date("2026-10-21")))
        XCTAssertTrue(day.isAfterToday(date("2026-10-22")))
    }
    func testAnchoredRequestsAndDateScopedKeysRemainStableUntilANewWindowIsChosen() {
        let a = window("2026-12-31T20:00:00Z"), b = window("2027-01-01T01:00:00Z")
        XCTAssertNotEqual(a.key(status: .present, year: .all), b.key(status: .present, year: .all))
        XCTAssertEqual(a.key(status: .past, year: .year(2025)), b.key(status: .past, year: .year(2025)))
        let row = sample("previous-window-today", start: "2026-12-31")
        XCTAssertEqual(results([row], .present, a), [row.id]); XCTAssertTrue(results([row], .present, b).isEmpty)
    }
    func testMalformedOrMissingDatesAreRejectedRatherThanFabricated() throws {
        let day = window("2026-10-21")
        XCTAssertFalse(day.contains(sample("reversed", start: "2026-10-22", end: "2026-10-20"), status: .present))
        XCTAssertFalse(day.isAfterToday(Date(timeIntervalSince1970: .infinity)))
        XCTAssertNil(CompetitionDateWindow(now: Date(timeIntervalSince1970: .nan)))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(sample("required-dates", start: "2026-10-21"))) as? [String: Any])
        payload.removeValue(forKey: "startDate")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(CompetitionSummary.self, from: JSONSerialization.data(withJSONObject: payload)))
        payload["startDate"] = "not-a-date"
        XCTAssertThrowsError(try decoder.decode(CompetitionSummary.self, from: JSONSerialization.data(withJSONObject: payload)))
    }
    func testFuturePastYearCompletesEmptyWithoutFetchingTheHistoricalCatalogue() async throws {
        let query = CompetitionQuery(languageCode: "en", region: .all, events: [.threeByThree], year: .year(2099), status: .past, dateWindow: window("2026-10-21"))
        let page = try await CompetitionService.fetchCompetitionsPage(query: query, page: 1)
        XCTAssertTrue(page.competitions.isEmpty); XCTAssertNil(page.nextPage); XCTAssertEqual(page.totalCount, 0)
    }

    func testHistoricalCatalogFilteringBenchmark() throws {
        let sampleDate = date("2026-01-01")
        let rows: [CompetitionSummary] = (0..<12_000).map { index in
            let day = sampleDate.addingTimeInterval(Double(-(index * 193 % 7000)) * 86_400)
            return .init(id: String(index), name: "Event \(index % 63)", shortDisplayName: nil,
                startDate: day, endDate: day, registrationOpen: nil, registrationClose: nil,
                competitorLimit: nil, venue: "", venueAddress: "", venueDetails: nil, city: "",
                countryISO2: index.isMultiple(of: 3) ? "CN" : "US", latitude: nil, longitude: nil,
                url: "", website: nil, dateRange: "", eventIDs: index.isMultiple(of: 7) ? ["222"] : ["333"],
                championshipTypes: nil, localizedRegionLineOverride: nil, localizedAddressLineOverride: nil,
                localizedStatusOverride: nil, localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
        }
        let day = window("2026-10-21")
        for year in [CompetitionYearFilter.all, .year(2025)] {
            let query = CompetitionQuery(languageCode: "en", region: .country("US"),
                events: [.threeByThree], year: year, status: .past, dateWindow: day)
            let expected = rows.filter {
                guard $0.countryISO2 == "US", $0.eventIDs.contains("333"), day.contains($0, status: .past) else { return false }
                if case .year(let value) = year { return CompetitionService.officialCompetitionYear(for: $0) == value }
                return true
            }.sorted { lhs, rhs in
                let ly = CompetitionService.officialCompetitionYear(for: lhs)
                let ry = CompetitionService.officialCompetitionYear(for: rhs)
                if ly != ry { return ly > ry }
                if lhs.endDate != rhs.endDate { return lhs.endDate > rhs.endDate }
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                let name = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return name == .orderedSame ? lhs.id < rhs.id : name == .orderedAscending
            }.map(\.id)
            var times: [Double] = []
            for _ in 0..<5 {
                let start = ProcessInfo.processInfo.systemUptime
                let actual = CompetitionService.filterCompetitions(rows, for: query)
                times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                XCTAssertEqual(actual.map(\.id), expected)
            }
            print("[Nov10Perf] historical_catalog rows=12000 year=\(year) matches=\(expected.count) ms=\(times)")
        }
    }
}
