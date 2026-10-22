import Foundation
import XCTest
@testable import CubeFlow

final class PublishedCompetitionTests: XCTestCase {
    private func result(_ id: Int, event: String = "333", round: String = "f", rank: Int = 1,
                        best: Int = 900, average: Int = 1000, person: String = "2020TEST01", name: String = "Alice Test",
                        format: String = "a", singleRecord: String? = nil, averageRecord: String? = nil) throws -> PublishedCompetitionResult {
        let row: [String: Any] = ["id": id, "competition_id": "Test2025", "event_id": event,
            "round_id": NSNull(), "round_type_id": round, "format_id": format, "pos": rank,
            "name": name, "wca_id": person, "country_iso2": "CN", "best": best, "average": average,
            "attempts": [best, -1, -2, 1100, 1200], "regional_single_record": singleRecord ?? NSNull() as Any,
            "regional_average_record": averageRecord ?? NSNull() as Any]
        return try JSONDecoder().decode(PublishedCompetitionResult.self, from: JSONSerialization.data(withJSONObject: row))
    }

    func testPublicationIsAuthoritativeNotAnElapsedDate() throws {
        let row = try result(1)
        XCTAssertEqual(PublishedCompetitionLifecycle.state(results: nil, requestFailed: false), .unknown)
        XCTAssertEqual(PublishedCompetitionLifecycle.state(results: nil, requestFailed: true), .failed)
        XCTAssertEqual(PublishedCompetitionLifecycle.state(results: [], requestFailed: false), .unpublished)
        let lifecycle = PublishedCompetitionLifecycle.state(results: [row], requestFailed: false)
        XCTAssertEqual(lifecycle, .published)
        XCTAssertEqual(lifecycle.primaryDestinations, ["info", "results", "scrambles"])
        XCTAssertFalse(lifecycle.primaryDestinations.contains("register"))
        XCTAssertFalse(lifecycle.primaryDestinations.contains("competitors"))
    }

    func testOnlyExistingRoundsBelongToTheirEvent() throws {
        let rows = try [result(1, round: "1"), result(2, round: "f"), result(3, event: "222", round: "f")]
        let data = PublishedCompetitionData(competitionID: "Test2025", results: rows, eventOrder: ["333", "222", "555"])
        XCTAssertEqual(data.eventIDs, ["333", "222"])
        XCTAssertEqual(data.rounds(for: "333").map(\.typeID), ["1", "f"])
        XCTAssertEqual(data.rounds(for: "222").map(\.typeID), ["f"])
        XCTAssertTrue(data.rounds(for: "555").isEmpty)
    }

    func testOfficialRanksDefineChampionsAndTiedPodiumsNotFastestBest() throws {
        let rows = try [result(1, rank: 1, best: 1000), result(2, rank: 2, best: 500, person: "2020TEST02"),
            result(3, rank: 2, best: 600, person: "2020TEST03"), result(4, rank: 4, best: 400, person: "2020TEST04"),
            result(5, round: "1", rank: 1, best: 200)]
        let data = PublishedCompetitionData(competitionID: "Test2025", results: rows)
        let final = try XCTUnwrap(data.finals.first)
        XCTAssertEqual(final.champions.map(\.id), [1])
        XCTAssertEqual(final.podium.map(\.id), [1, 2, 3])
        XCTAssertEqual(data.finals.count, 1)
    }

    func testCombinedFinalAndUnsuccessfulAverageDoNotInventMedals() throws {
        let rows = try [result(1, round: "c", rank: 1), result(2, round: "c", rank: 2, average: -1)]
        let final = try XCTUnwrap(PublishedCompetitionData(competitionID: "Test2025", results: rows).finals.first)
        XCTAssertEqual(final.podium.map(\.id), [1])
    }

    @MainActor
    func testOfficialHistoricalCutoffAndBFinalRoundTypes() throws {
        let rows = try [result(1, round: "h"), result(2, round: "d"), result(3, round: "e"),
            result(4, round: "g"), result(5, round: "b"), result(6, round: "c")]
        let data = PublishedCompetitionData(competitionID: "Test2025", results: rows)
        XCTAssertEqual(data.rounds.map(\.typeID), ["h", "d", "e", "g", "b", "c"])
        XCTAssertEqual(data.finals.map(\.typeID), ["c"])
        XCTAssertTrue(PublishedCompetitionStrings.round("d", language: "en").hasPrefix("First round"))
        XCTAssertTrue(PublishedCompetitionStrings.round("e", language: "en").hasPrefix("Second round"))
        XCTAssertTrue(PublishedCompetitionStrings.round("g", language: "en").hasPrefix("Semi Final"))
        XCTAssertEqual(PublishedCompetitionStrings.round("h", language: "en"), "Qualification round")
        XCTAssertEqual(PublishedCompetitionStrings.round("b", language: "en"), "B Final")
    }

    func testNameAndWCAIDSearchPrioritizesConnectedUserOnlyWhenPresent() throws {
        let rows = try [result(1), result(2, person: "2020TEST02", name: "Zoe Chen")]
        let data = PublishedCompetitionData(competitionID: "Test2025", results: rows)
        XCTAssertEqual(data.people(query: "", currentWCAID: "2020TEST02").map(\.id), ["2020TEST02", "2020TEST01"])
        XCTAssertEqual(data.people(query: "zoe", currentWCAID: nil).map(\.id), ["2020TEST02"])
        XCTAssertEqual(data.people(query: "TEST01", currentWCAID: "2020TEST02").map(\.id), ["2020TEST01"])
        XCTAssertEqual(data.people(query: "", currentWCAID: "UNKNOWN").map(\.id), ["2020TEST01", "2020TEST02"])
    }

    func testRecordsMapFromOfficialFields() throws {
        XCTAssertEqual(try result(1, singleRecord: "WR").singleBadge, "WR")
        XCTAssertEqual(try result(1, averageRecord: "AS").averageBadge, "CR")
        XCTAssertEqual(try result(1, singleRecord: "NR").singleBadge, "NR")
        XCTAssertNil(try result(1, singleRecord: "PB").singleBadge)
    }

    func testOfficialResultFormatsAndAttempts() throws {
        let time = try result(1)
        XCTAssertEqual(time.formatted(-1), "DNF")
        XCTAssertEqual(time.formatted(-2), "DNS")
        XCTAssertEqual(time.formatted(6123), "1:01.23")
        let moves = try result(2, event: "333fm", best: 25, average: 2533, format: "m")
        XCTAssertEqual(moves.formatted(25), "25")
        XCTAssertEqual(moves.formatted(2533, average: true), "25.33")
        let blind = try result(3, event: "333mbf", format: "1")
        XCTAssertEqual(blind.formatted(970360001), "3/4 1:00:00")
        XCTAssertFalse(blind.usesAverage)
        XCTAssertEqual(time.attempts.count, 5)
    }

    func testCutoffOmitsUnperformedAttemptsButRetainsDNFAndDNSAndBestOfMean() throws {
        let payload = #"{"id":1,"competition_id":"Test2025","event_id":"333bf","round_type_id":"f","format_id":"3","pos":1,"name":"A","wca_id":"2020TEST01","country_iso2":"CN","best":2500,"average":-1,"attempts":[2500,-1,-2,0,0]}"#.data(using: .utf8)!
        let row = try JSONDecoder().decode(PublishedCompetitionResult.self, from: payload)
        XCTAssertEqual(row.performedAttempts, [2500, -1, -2])
        XCTAssertFalse(row.usesAverage)
        XCTAssertTrue(row.showsAverage)
        XCTAssertEqual(row.formatted(row.average, average: true), "DNF")
    }

    func testResultsRejectWrongCompetitionAndDuplicateIDs() throws {
        let payload = #"[{"id":1,"competition_id":"Test2025","event_id":"333","round_type_id":"f","format_id":"a","pos":1,"name":"A","wca_id":"2020TEST01","country_iso2":"CN","best":1000,"average":1000,"attempts":[1000]}]"#.data(using: .utf8)!
        XCTAssertEqual(try PublishedCompetitionService.decodeResults(payload, competitionID: "Test2025").count, 1)
        XCTAssertThrowsError(try PublishedCompetitionService.decodeResults(payload, competitionID: "Wrong2025"))
        let repeated = "[" + String(data: payload, encoding: .utf8)!.dropFirst().dropLast() + "," + String(data: payload, encoding: .utf8)!.dropFirst().dropLast() + "]"
        XCTAssertThrowsError(try PublishedCompetitionService.decodeResults(Data(repeated.utf8), competitionID: "Test2025"))
        XCTAssertFalse(PublishedCompetitionService.validCompetitionID("../Test2025"))
    }

    func testPublishedScramblesPreserveTextAndSeparateExtraGroups() throws {
        let payload = #"[{"id":1,"competition_id":"Test2025","event_id":"333","round_id":10,"round_type_id":"f","group_id":"A","is_extra":true,"scramble_num":1,"scramble":" R U'\nF2 "},{"id":2,"competition_id":"Test2025","event_id":"333","round_id":10,"round_type_id":"f","group_id":"A","is_extra":false,"scramble_num":1,"scramble":"D2"},{"id":3,"competition_id":"Test2025","event_id":"333","round_id":10,"round_type_id":"f","group_id":"B","is_extra":false,"scramble_num":1,"scramble":"L2"},{"id":4,"competition_id":"Test2025","event_id":"clock","round_id":11,"round_type_id":"1","group_id":"A","is_extra":false,"scramble_num":1,"scramble":"UR3+"}]"#.data(using: .utf8)!
        let rows = try PublishedCompetitionService.decodeScrambles(payload, competitionID: "Test2025")
        let sets = PublishedScrambleSet.grouped(rows)
        XCTAssertEqual(sets.count, 3)
        let first = try XCTUnwrap(sets.first { $0.eventID == "333" && $0.groupID == "A" })
        XCTAssertEqual(first.scrambles.map(\.id), [2, 1])
        XCTAssertEqual(first.scrambles.last?.scramble, " R U'\nF2 ")
        XCTAssertEqual(rows.last?.puzzleKey, "clk")
        XCTAssertThrowsError(try PublishedCompetitionService.decodeScrambles(payload, competitionID: "Wrong2025"))
    }

    @MainActor
    func testNativePresentationUsesExistingGlyphsBadgesAndLocalizedNames() {
        XCTAssertNotNil(CompetitionEventIconFont.glyph(for: "333"))
        XCTAssertEqual(PublishedCompetitionStrings.text("scrambles", "zh-Hans"), "打乱")
        XCTAssertEqual(PublishedCompetitionStrings.round("f", language: "en"), "Final")
    }

    func testFullSizeScrambleSelectionIsBoundedAndPreservesSelections() {
        let events = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh", "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf"]
        let sets = (0..<92).map { index in
            PublishedScrambleSet(id: "set\(index)", eventID: events[index % events.count],
                roundKey: "\(events[index % events.count])|\(index / events.count % 3)",
                roundTypeID: ["1", "2", "f"][index / events.count % 3],
                groupID: index < 51 ? "A" : "B", scrambles: [])
        }
        let start = PublishedCompetitionClock.now()
        for _ in 0..<1000 {
            let selected = PublishedScrambleSelection(sets: sets, eventOrder: events, event: "333", round: "333|2", group: "B")
            XCTAssertEqual(selected.events, events)
            XCTAssertEqual(selected.roundOptions.map(\.type), ["1", "2", "f"])
            XCTAssertEqual(selected.currentSet?.groupID, "B")
            XCTAssertEqual(selected.roundID, "333|2")
        }
        let elapsed = PublishedCompetitionClock.milliseconds(since: start)
        print("[CompetitionCritical] 1000 full-size selections=\(elapsed)ms")
        XCTAssertLessThan(elapsed, 2000, "Selection must not recursively rebuild lists inside predicates")
        let fallback = PublishedScrambleSelection(sets: sets, eventOrder: events, event: "missing", round: "missing", group: "missing")
        XCTAssertEqual(fallback.eventID, "333")
        XCTAssertEqual(fallback.roundOptions.first?.type, "1")
        XCTAssertEqual(fallback.currentSet?.groupID, "A")
    }

    @MainActor
    func testSharedLivePresentationKeepsOfficialValuesAttemptsAndRecordTags() throws {
        let row = try result(1, singleRecord: "WR", averageRecord: "AS")
        let values = PublishedResultPresentation.values(row)
        XCTAssertEqual(values.map(\.id), ["average", "best"])
        XCTAssertEqual(values.map(\.text), ["10.00", "9.00"])
        XCTAssertEqual(values.map(\.recordTag), ["CR", "WR"])
        XCTAssertEqual(row.performedAttempts.map { row.formatted($0) }, ["9.00", "DNF", "DNS", "11.00", "12.00"])
        let blind = try result(2, event: "333mbf", average: 0, format: "1")
        XCTAssertEqual(PublishedResultPresentation.values(blind).map(\.id), ["best"])
        let mean = try result(3, format: "m")
        XCTAssertEqual(PublishedResultPresentation.title("average", result: mean, language: "en"), "Mean")
    }
}
