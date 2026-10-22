import XCTest
@testable import CubeFlow

@MainActor
final class ExploreRecentRecordMergeTests: XCTestCase {
    private final class PartialProvider: ExploreRecentRecordsProviding {
        let records: [WCARecentRecord]
        private(set) var calls = 0
        init(records: [WCARecentRecord]) { self.records = records }
        func cached() async -> ExploreRecentRecordsSnapshot? { nil }
        func refresh() async throws -> ExploreRecentRecordsSnapshot {
            calls += 1
            return .init(records: records, fetchedAt: Date(), hasPartialFailure: true)
        }
    }
    func testPartialSourceFailureIsNotReportedAsFullyFreshSuccess() async {
        let store = ExploreStore(recentRecordsProvider: PartialProvider(records: [live()]))
        await store.loadRecentRecords(language: "en", force: true)
        XCTAssertEqual(store.recordsState, .failedWithCache)
        XCTAssertEqual(store.recentRecordItems.count, 1)
    }
    func testPartialOfficialSourceFailureRetriesInsideTheNormalFreshnessWindow() async {
        let provider = PartialProvider(records: [live()])
        let store = ExploreStore(recentRecordsProvider: provider)
        await store.loadRecentRecords(language: "en", force: true)
        await store.loadRecentRecords(language: "en")
        XCTAssertEqual(provider.calls, 2, "Successful Live traffic must not suppress the failed official-source retry")
        XCTAssertEqual(store.recordsState, .failedWithCache)
        XCTAssertEqual(store.recentRecordItems.count, 1)
        XCTAssertEqual(store.recentRecordItems.first?.recordContext?.sourceLabel, "WCA Live \u{b7} Provisional")
    }
    func testOfficialHTTP403IsNotDecodedAsAnEmptyRecognizedRecordFeed() throws {
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://www.worldcubeassociation.org/api/v0/results/records")!,
            statusCode: 403, httpVersion: nil, headerFields: nil))
        XCTAssertThrowsError(try WCAExplorePublicDataService.validateResponse(response)) { error in
            guard case WCAExplorePublicDataError.httpStatus(403) = error else {
                return XCTFail("Expected the actual official-source HTTP error, not an empty success")
            }
        }
    }
    private func official(_ id: Int, type: String = "single", value: Int = 800) -> WCAPublicResult {
        WCAPublicResult(id: id, personId: "2020TEST01", personName: "Fixture Cuber", countryId: "China",
            competitionCountryId: "China", competitionId: "Fixture2026", competitionName: "Fixture Open",
            startDate: "2026-10-05", eventId: "333", attempts: [800, 900, 1000, 1000, 1200],
            best: 800, average: 1000, value: value, type: type, regionalSingleRecord: "WR", regionalAverageRecord: "AS")
    }
    private func live(type: String = "single", value: Int = 800) -> WCARecentRecord {
        WCARecentRecord(id: "live-fixture-\(type)", tag: "WR", type: type, attemptResult: value,
            result: .init(id: "live-result", person: .init(id: "live-person", wcaId: "2020TEST01",
                name: "Fixture Cuber", country: .init(iso2: "CN", name: "China")),
                round: .init(id: "live-round", competitionEvent: .init(event: .init(id: "333", name: "3x3x3"),
                    competition: .init(id: "live-competition", wcaId: "Fixture2026", name: "Fixture Open")))))
    }
    func testOfficialAchievementReplacesLiveDuplicateWithoutInventingLiveIDs() throws {
        let records = ExploreRecentRecordMerge.merge(live: [live(), live(type: "average", value: 1000)], official: [official(1)])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.filter { $0.officialResult != nil }.count, 1)
        let item = try XCTUnwrap(WCAExplorePublicDataService.recentRecordsCandidate(records, language: "en")
            .first(where: { $0.id == "records.recent" })?.items.last)
        XCTAssertEqual(item.content, .publishedRecord(id: "official-1-single", competitionID: "Fixture2026"))
        XCTAssertEqual(item.publishedResultDeepLink,
            PublishedCompetitionResultDeepLink(competitionID: "Fixture2026", resultID: 1, eventID: "333"))
        XCTAssertEqual(item.recordContext?.sourceLabel, "WCA \u{b7} Official")
        XCTAssertEqual(records.first?.result.round.id, "live-round")
        XCTAssertNil(WCAExplorePublicDataService.recentRecordsCandidate([live()], language: "en")
            .first?.items.first?.publishedResultDeepLink)
    }
    func testDifferentValuesAndTypesAreDistinctAndOfficialTagsRemainAuthoritative() {
        let rows = ExploreRecentRecordMerge.merge(live: [live(value: 900)],
            official: [official(1), official(2, type: "average", value: 1000)])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.tag, "WR", "Most recent official id sorts first; no rank becomes a record")
        XCTAssertEqual(rows.first(where: { $0.type == "average" })?.tag, "CR")
        XCTAssertTrue(rows.contains { $0.attemptResult == 900 && $0.officialResult == nil })
        let invalid = official(3, value: -1)
        XCTAssertTrue(ExploreRecentRecordMerge.merge(live: [], official: [invalid]).isEmpty)
    }
}
