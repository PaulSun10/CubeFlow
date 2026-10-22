import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CubingLiveRecordIndicatorTests: XCTestCase {
    private func source(single: Any? = nil, average: Any? = nil, personalSingle: Any? = nil, personalAverage: Any? = nil) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: CubingChinaModernLiveFixtures.beijing) as? [String: Any])
        var values = try XCTUnwrap(object["results"] as? [[String: Any]])
        values[0]["regionalSingleRecord"] = single ?? NSNull()
        values[0]["regionalAverageRecord"] = average ?? NSNull()
        values[0]["personalSingleRecord"] = personalSingle ?? NSNull()
        values[0]["personalAverageRecord"] = personalAverage ?? NSNull()
        values[0]["rankSingleMarker"] = "WR1"
        values[0]["rankAverageMarker"] = "WR3"
        object["results"] = values
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testCubingBridgeRetainsExplicitPersonalSingleAndAverageRecords() async throws {
        let snapshot = try JSONDecoder().decode(CubingChinaLiveSnapshot.self,
            from: source(personalSingle: "PR", personalAverage: "PR"))
        let transport = FakeCubingChinaTransport(snapshot: snapshot)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [snapshot.round])
        let bridge = CompetitionCubingLiveSession()
        bridge.configure(with: CubingChinaLivePresentation.content(bootstrap, language: "en"), transport: transport)
        bridge.start(); defer { bridge.stop() }
        for _ in 0..<150 where bridge.resultRows.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        let row = try XCTUnwrap(bridge.resultRows.first)
        XCTAssertEqual(row.singleRecordTag, "PR")
        XCTAssertEqual(row.averageRecordTag, "PR")
        XCTAssertEqual(row.bestResultText, "1:27.47")
        XCTAssertEqual(row.averageResultText, "1:35.93")
        XCTAssertEqual(row.rankText, "1")
    }
    func testMalformedRecordMetadataDoesNotDiscardValidResultValues() throws {
        let data = try source(single: true, average: 42, personalSingle: ["PR"], personalAverage: ["flag": "PR"])
        let snapshot = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: data)
        let value = try XCTUnwrap(snapshot.results.first)
        XCTAssertEqual(value.best, 8747)
        XCTAssertEqual(value.average, 9593)
        let preview = CubingChinaLivePresentation.preview(value, language: "en")
        XCTAssertNil(preview.singleRecordTag); XCTAssertNil(preview.averageRecordTag)
        XCTAssertEqual(snapshot.results.count, 17)
    }
    func testWRCRNRPRSingleAverageAndAllResultsUseOnlyExplicitMetadata() throws {
        let cases: [(String?, String?, String?, String?, String?, String?)] = [
            ("WR", "AsR", "PR", "PR", "WR", "CR"),
            ("CR", "NR", nil, nil, "CR", "NR"),
            (nil, nil, "PR", nil, "PR", nil),
            (nil, nil, nil, "PR", nil, "PR"),
            ("WR1", "WR3", nil, nil, nil, nil),
            (nil, nil, nil, nil, nil, nil),
            ("unknown", "", "false", "NR", nil, nil)
        ]
        for (single, average, personalSingle, personalAverage, expectedSingle, expectedAverage) in cases {
            let snapshot = try JSONDecoder().decode(CubingChinaLiveSnapshot.self,
                from: source(single: single, average: average, personalSingle: personalSingle, personalAverage: personalAverage))
            let value = try XCTUnwrap(snapshot.results.first)
            let preview = CubingChinaLivePresentation.preview(value, language: "en")
            let round = CubingChinaLivePresentation.round(snapshot, rounds: [snapshot.round], language: "en")
            let all = try XCTUnwrap(CubingChinaLivePresentation.competitor([value], rounds: [snapshot.round], language: "en")?.results.first)
            XCTAssertEqual(preview.singleRecordTag, expectedSingle); XCTAssertEqual(preview.averageRecordTag, expectedAverage)
            XCTAssertEqual(round.results.first?.singleRecordTag, expectedSingle); XCTAssertEqual(round.results.first?.averageRecordTag, expectedAverage)
            XCTAssertEqual(all.singleRecordTag, expectedSingle); XCTAssertEqual(all.averageRecordTag, expectedAverage)
            XCTAssertEqual(value.position, 1, "Position must never determine a record")
        }
        // Shared WCA/official regional normalization is not expanded to PR or rank markers.
        XCTAssertNil(PublishedCompetitionResult.recordBadge("PR"))
        XCTAssertNil(PublishedCompetitionResult.recordBadge("WR1"))
    }
    nonisolated private func decodeOffActor(_ data: Data) throws -> CubingChinaLiveSnapshot {
        try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: data)
    }
    func testCubingNormalizationAndCodableRoundTripKeepNonRecordDataStrict() throws {
        let source = try source(single: " wr ", average: " AsR\n", personalSingle: " pr ", personalAverage: "PR")
        let value = try decodeOffActor(source)
        XCTAssertEqual(value.results[0].singleIndicator, "WR")
        XCTAssertEqual(value.results[0].averageIndicator, "CR")
        let roundTrip = try decodeOffActor(JSONEncoder().encode(value))
        XCTAssertEqual(roundTrip, value)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        var results = try XCTUnwrap(json["results"] as? [[String: Any]])
        results[0]["best"] = "not-a-score"
        json["results"] = results
        XCTAssertThrowsError(try decodeOffActor(JSONSerialization.data(withJSONObject: json)), "Only record decorations are lossy")
    }

}
