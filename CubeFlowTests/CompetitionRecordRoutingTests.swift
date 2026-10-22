import XCTest
@testable import CubeFlow

@MainActor
final class CompetitionRecordRoutingTests: XCTestCase {
    func testOfficialContinentalMarkersNormalizeWithoutInventingUnknownRecords() {
        for tag in ["AfR", "AsR", "ER", "NAR", "OcR", "SAR", "CR", "AS"] {
            XCTAssertEqual(PublishedCompetitionResult.recordBadge(tag), "CR")
        }
        for tag in [nil, "", "PB", "PR", "unverified"] as [String?] {
            XCTAssertNil(PublishedCompetitionResult.recordBadge(tag))
        }
        XCTAssertEqual(PublishedCompetitionResult.highestBadge(["NR", "AsR", "WR"]), "WR")
        XCTAssertEqual(PublishedCompetitionResult.highestBadge(["NR", "AsR"]), "CR")
        XCTAssertNil(PublishedCompetitionResult.highestBadge([nil, "PR"]))
    }

    func testActualOfficialRecordsReachRowsEventAndRoundSelectors() throws {
        let beijing = try PublishedCompetitionService.decodeResults(CompetitionRecordFixtures.beijing,
            competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: beijing)
        let continental = try XCTUnwrap(beijing.first { $0.id == 8581097 })
        XCTAssertEqual(continental.singleBadge, "NR")
        XCTAssertEqual(continental.averageBadge, "CR")
        XCTAssertEqual(PublishedResultPresentation.values(continental).map(\.recordTag), ["CR", "NR"])
        XCTAssertEqual(data.roundRecordTags["777|954912"], "CR")
        XCTAssertEqual(data.roundRecordTags["777|954913"], "WR")
        XCTAssertEqual(data.eventRecordTags["777"], "WR")
        XCTAssertEqual(data.eventRecordTags["444"], "NR")
        XCTAssertEqual(data.roundRecordTags["666|954910"], "WR", "The same round also contains AsR")
        let guangzhou = try PublishedCompetitionService.decodeResults(CompetitionRecordFixtures.guangzhou,
            competitionID: "GuangzhouGrandOpen2026")
        let other = PublishedCompetitionData(competitionID: "GuangzhouGrandOpen2026", results: guangzhou)
        XCTAssertEqual(other.eventRecordTags["333"], "WR")
        XCTAssertEqual(other.eventRecordTags["555"], "WR")
        XCTAssertEqual(other.eventRecordTags["clock"], "NR")
        XCTAssertNil(other.eventRecordTags["222"])
    }

    func testOfficialRecordTargetResolvesActualEventAndNonDefaultRoundOnly() throws {
        let id = "BeijingAutumnRivalry2026"
        let rows = try PublishedCompetitionService.decodeResults(CompetitionRecordFixtures.beijing, competitionID: id)
        let data = PublishedCompetitionData(competitionID: id, results: rows)
        let target = PublishedCompetitionResultDeepLink(competitionID: id, resultID: 8581097, eventID: "777")
        XCTAssertEqual(target.result(in: data)?.roundKey, "777|954912")
        XCTAssertNotEqual(target.result(in: data)?.roundKey, data.rounds(for: "777").last?.id)
        XCTAssertNil(PublishedCompetitionResultDeepLink(competitionID: "Wrong2026", resultID: 8581097, eventID: "777").result(in: data))
        XCTAssertNil(PublishedCompetitionResultDeepLink(competitionID: id, resultID: 8581097, eventID: "666").result(in: data))
        XCTAssertNil(PublishedCompetitionResultDeepLink(competitionID: id, resultID: -1, eventID: "777").result(in: data))
    }

    func testChinaAlwaysUsesItsOwnAvailableLiveProviderIncludingRecordEntry() {
        XCTAssertTrue(CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: true,
            explicitWCALive: true, hasContent: true))
        XCTAssertTrue(CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: true,
            explicitWCALive: false, hasContent: true))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.usesCubingChinaLive(cubingChina: true,
            explicitWCALive: false, hasContent: false))
        for lifecycle in [PublishedCompetitionLifecycle.published, .unpublished] {
            XCTAssertEqual(CompetitionDetailNavigationPolicy.selection(lifecycle: lifecycle, cubingChina: true,
                showLive: true, explicitLive: true, primary: .live, section: .info).primary, .live)
        }
    }

    func testOfficialSourceRequestsValidationWithoutDependingOnlyOnCompletion() {
        XCTAssertTrue(CompetitionDetailNavigationPolicy.shouldCheckPublication(competitionEnded: false, explicitPublishedResult: true))
        XCTAssertTrue(CompetitionDetailNavigationPolicy.shouldCheckPublication(competitionEnded: true, explicitPublishedResult: false))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.shouldCheckPublication(competitionEnded: false, explicitPublishedResult: false))
        XCTAssertEqual(CompetitionService.canonicalWCALiveCompetitionURL(for: 123)?.absoluteString,
            "https://live.worldcubeassociation.org/competitions/123")
    }
}
