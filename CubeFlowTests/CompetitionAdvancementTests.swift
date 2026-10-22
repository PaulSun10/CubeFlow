import XCTest
import SwiftUI
@testable import CubeFlow

nonisolated private struct GroupedEvidenceExtras: CubingChinaLiveExtrasTransport {
    let records: [CubingChinaLiveResult]
    let podiums: [CubingChinaLivePodium]
    func records(slug: String) async throws -> [CubingChinaLiveResult] { records }
    func podiums(slug: String) async throws -> [CubingChinaLivePodium] { podiums }
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank] { [] }
}

@MainActor final class CompetitionAdvancementTests: XCTestCase {
    private func snapshot(_ attempts: [[Int]], ranks: [Int?]? = nil, format: String = "1",
                          type: String = "ranking", level: Int = 3, number: Int = 1,
                          cutoff: [String: Int]? = nil, final: Bool = false, record: Bool = false) throws -> CubingChinaLiveSnapshot {
        var rules: [String: Any] = ["id": 200 + number, "format": format,
            "advancementCondition": ["type": type, "level": level]]
        if let cutoff { rules["cutoff"] = cutoff }
        if final { rules["advancementCondition"] = NSNull() }
        let round: [String: Any] = ["id": number, "competitionId": 100, "competitionRoundId": 200 + number,
            "revision": 1, "eventId": "333", "roundNumber": number, "status": final ? "finished" : "live", "round": rules]
        let rows = attempts.enumerated().map { index, values -> [String: Any] in
            let positive = values.filter { $0 > 0 }
            var row: [String: Any] = ["id": number * 1000 + index + 1, "competitionId": 100,
                "competitionRoundId": 200 + number, "registrationId": index + 10, "userId": index + 100,
                "eventId": "333", "roundNumber": number, "attempts": values,
                "best": positive.min() ?? 0, "average": values.count == 5 && !values.contains(0) ? values[2] : 0,
                "competitor": ["id": index + 100, "number": index + 1, "name": "Person \(index)", "wcaId": "2019TEST01"]]
            if let rank = ranks?[index] ?? (positive.isEmpty ? nil : index + 1) { row["position"] = rank }
            if record, index == 0 { row["regionalSingleRecord"] = "WR" }
            return row
        }
        return try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: ["round": round, "results": rows]))
    }

    func testIncompleteFieldIsYellowAndCompletedFieldIsGreen() throws {
        let incomplete = try snapshot([[100], [200], [300], [], [], [], [], []])
        let states = CompetitionAdvancementCalculation.states(incomplete, isFinal: false)
        XCTAssertEqual(states["ccc-result:1001"], .possible)
        XCTAssertEqual(states["ccc-result:1003"], .possible)
        let complete = try snapshot((1...8).map { [$0 * 100] })
        let finished = CompetitionAdvancementCalculation.states(complete, isFinal: false)
        XCTAssertEqual(finished.count, 3)
        XCTAssertEqual(finished["ccc-result:1001"], .confirmed)
    }

    func testTiesAtSeventyFivePercentBoundaryAreExcludedTogether() throws {
        let value = try snapshot([[100], [200], [300], [400], [500], [600], [600], [800]],
            ranks: [1, 2, 3, 4, 5, 6, 6, 8], level: 10)
        let states = CompetitionAdvancementCalculation.states(value, isFinal: false)
        XCTAssertEqual(states.count, 5)
        XCTAssertNil(states["ccc-result:1006"])
        XCTAssertNil(states["ccc-result:1007"])
    }

    func testPercentageAndStrictResultThresholdRequireActualRule() throws {
        let attempts = (1...8).map { [$0 * 100] }
        XCTAssertEqual(CompetitionAdvancementCalculation.states(try snapshot(attempts, type: "percent", level: 25), isFinal: false).count, 2)
        XCTAssertEqual(CompetitionAdvancementCalculation.states(try snapshot(attempts, type: "attempt-result", level: 300), isFinal: false).count, 2)
        XCTAssertTrue(CompetitionAdvancementCalculation.states(try snapshot(attempts, type: "unknown"), isFinal: false).isEmpty)
    }

    func testIncompleteAverageCannotBeGreenEvenIfClinched() throws {
        let value = try snapshot([[1, 1, 1, 1, 0]] + (2...8).map { Array(repeating: $0 * 100, count: 5) }, format: "a", level: 1)
        XCTAssertEqual(CompetitionAdvancementCalculation.states(value, isFinal: false)["ccc-result:1001"], .possible)
        let holes = try snapshot([[1, 0, 1, 0, 0]] + (2...8).map { Array(repeating: $0 * 100, count: 5) }, format: "a")
        XCTAssertTrue(CompetitionAdvancementCalculation.states(holes, isFinal: false).isEmpty)
    }

    func testCutoffFailureDoesNotAcquireFictitiousAverageOrPassTimeThreshold() throws {
        let value = try snapshot([[500, 500, 0, 0, 0]] + (2...8).map { Array(repeating: $0 * 100, count: 5) },
            format: "a", type: "attempt-result", level: 100, cutoff: ["attemptResult": 300, "numberOfAttempts": 2])
        XCTAssertNil(CompetitionAdvancementCalculation.states(value, isFinal: false)["ccc-result:1001"])
    }

    func testOpenNextRoundUsesRosterNotQualifyingRankAndSharesCardEvidence() throws {
        let first = try snapshot((1...8).map { [$0 * 100] })
        let next = try snapshot([[100]], number: 2)
        let rounds = [first.round, next.round]
        XCTAssertTrue(CubingChinaLivePresentation.advancement(first, rounds: rounds).isEmpty)
        let roster = Set(next.results.map(\.userId))
        let states = CubingChinaLivePresentation.advancement(first, rounds: rounds, nextParticipants: roster)
        XCTAssertEqual(states.count, 1)
        let person = try XCTUnwrap(CubingChinaLivePresentation.competitor([first.results[0], next.results[0]], rounds: rounds, language: "en"))
        XCTAssertEqual(person.results.first?.isAdvancing, true)
        let absent = try XCTUnwrap(CubingChinaLivePresentation.competitor([first.results[1]], rounds: rounds, language: "en", knownAdvancement: states))
        XCTAssertNil(absent.results.first?.isAdvancing, "Rank two does not prove participation or elimination")
    }

    func testOfficialRoundAndAllResultsHaveIdenticalVerifiedFlags() throws {
        let rows = try PublishedCompetitionService.decodeResults(CompetitionPhysicalRegressionFixtures.beijingPublishedResults, competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: rows)
        let card = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2016KOLA02", data: data, language: "en"))
        for round in data.rounds {
            for row in PublishedCompetitionPresentation.round(round, language: "en", data: data).results where row.personWCAID == card.wcaID {
                XCTAssertEqual(card.results.first { $0.id == row.id }?.isAdvancing, row.isAdvancing)
            }
        }
        XCTAssertTrue(card.results.contains { $0.isAdvancing == true })
    }

    func testCompleteDownloadedBeijingUsesActualNextRosterNotTopTwoHundred() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/competition-physical-regressions")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("beijing-live-333-2.json").path) else {
            throw XCTSkip("Requires the full public responses; deterministic roster coverage remains available")
        }
        let decoder = JSONDecoder()
        let first = try decoder.decode(CubingChinaLiveSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("beijing-live-333-1.json")))
        let next = try decoder.decode(CubingChinaLiveSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("beijing-live-333-2.json")))
        let rounds = try decoder.decode([CubingChinaLiveRound].self, from: Data(contentsOf: root.appendingPathComponent("beijing-rounds.json")))
        let roster = Set(next.results.map(\.userId))
        let list = CubingChinaLivePresentation.round(first, rounds: rounds, language: "en", nextParticipants: roster)
        XCTAssertEqual(first.results.count, 325)
        XCTAssertEqual(next.results.count, 190)
        for value in first.results {
            XCTAssertEqual(list.results.first { $0.id == "ccc-result:\(value.id.rawValue)" }?.isAdvancing,
                roster.contains(value.userId) ? true : nil)
        }
        XCTAssertLessThan(list.results.filter { $0.isAdvancing == true }.count, 200,
            "The rule permits 200, but the actual next-round roster is authoritative")
    }

    func testSessionFetchesOnlyAdjacentRosterAndPreservesSelection() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] })
        let next = try snapshot([[100]], number: 2)
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round])
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        session.start(); defer { session.stop() }
        for _ in 0..<100 where session.nextParticipants(for: first.round) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(session.selectedKey, first.round.key)
        XCTAssertEqual(session.nextParticipants(for: first.round), Set(next.results.map(\.userId)))
        XCTAssertEqual(session.knownAdvancement["ccc-result:1001"], .confirmed)
        XCTAssertNil(session.knownAdvancement["ccc-result:1002"])
        XCTAssertTrue(transport.requestedKeys.allSatisfy { $0 == first.round.key || $0 == next.round.key })
    }
    func testColdGroupedEvidenceUsesCompleteFieldAndAdjacentRosterWithoutSelectingResults() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] }, record: true)
        let next = try snapshot([[100]], number: 2, final: true)
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026",
            rounds: [first.round, next.round]), transport: transport)
        let selection = session.selectedKey
        let partial = CubingChinaLiveSnapshot(round: first.round, results: Array(first.results.prefix(3)))
        XCTAssertNil(CubingChinaLivePresentation.round(partial, rounds: session.rounds, language: "en",
            advancementStates: session.knownAdvancement).results.first?.isAdvancing)
        await session.loadAdvancementEvidence(for: [first.round.key, next.round.key])
        XCTAssertNil(session.snapshot, "Evidence must not require or mutate the selected Results snapshot")
        XCTAssertEqual(session.selectedKey, selection)
        XCTAssertEqual(session.knownAdvancement["ccc-result:1001"], .confirmed)
        XCTAssertNil(session.knownAdvancement["ccc-result:1002"], "Rank/record alone cannot authorize advancement")
        XCTAssertEqual(session.knownAdvancement["ccc-result:2001"], .confirmed, "Final podium, not next-round advancement")
        let count = transport.resultRequests
        await session.loadAdvancementEvidence(for: [first.round.key, next.round.key])
        XCTAssertEqual(transport.resultRequests, count, "Known revision-scoped evidence should be reused")
    }

    func testStoppedGroupedEvidenceRejectsLateAdjacentRoster() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] })
        let next = try snapshot([[100]], number: 2)
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        transport.holdResults(for: next.round.key)
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026",
            rounds: [first.round, next.round]), transport: transport)
        let task = Task { await session.loadAdvancementEvidence(for: [first.round.key]) }
        for _ in 0..<100 where transport.heldCount == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(transport.heldCount, 1)
        session.stop(); task.cancel(); transport.releaseHeldResults()
        await task.value
        XCTAssertTrue(session.knownAdvancement.isEmpty)
        XCTAssertNil(session.nextParticipants(for: first.round))
    }

    func testGroupedDestinationMountLoadsEvidenceWithoutVisitingResults() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] }, record: true)
        let final = try snapshot((1...8).map { [$0 * 100] }, number: 2, final: true)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, final.round])
        let podium = CubingChinaLivePodium(eventId: "333", roundNumber: 2,
            results: Array(final.results.prefix(3)), group: nil, groupIndex: nil)
        let fixture = GroupedEvidenceExtras(records: [first.results[0]], podiums: [podium])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for destination in ["records", "podiums"] {
            let transport = FakeCubingChinaTransport(snapshot: first, additional: [final])
            let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
            let extras = CubingChinaLiveExtrasStore()
            extras.refresh(bootstrap, transport: fixture)
            for _ in 0..<100 where extras.isLoading { try await Task.sleep(nanoseconds: 5_000_000) }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.windowLevel = .alert + 1
            let view = CubingChinaUnifiedLiveContent(session: session, extras: extras, card: CompetitionResultCardState(),
                roundSelection: .constant(session.selectedKey.selectionID), language: "en", loadCompetitor: { _ in nil }) { EmptyView() }
                .environment(\.competitionLivePreviewDestination, destination)
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; session.stop(); extras.stop() }
            let resultID = destination == "records" ? "ccc-result:1001" : "ccc-result:2001"
            for _ in 0..<100 where session.knownAdvancement[resultID] == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(session.knownAdvancement[resultID], .confirmed, destination)
            XCTAssertNil(session.snapshot)
            XCTAssertEqual(transport.connectionCount, 0, "No Results visit or stream start was needed")
            XCTAssertTrue(transport.requestedKeys.allSatisfy { [first.round.key, final.round.key].contains($0) })
        }
    }

    func testAdjacentRosterRevisionRevokesOldEvidenceAndRefreshesWithoutChangingSelection() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] })
        let next = try snapshot([[100]], number: 2)
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), transport: transport)
        session.start(); defer { session.stop() }
        for _ in 0..<100 where session.nextParticipants(for: first.round) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot([[100], [200]], number: 2))) as! [String: Any]
        var round = object["round"] as! [String: Any]; round["revision"] = 2; object["round"] = round
        object["results"] = Array((object["results"] as! [[String: Any]]).dropFirst())
        let changed = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        transport.setSnapshot(changed)
        try transport.emit("round.competitor.quit", payload: ["round": round, "upsertedResults": [], "removedResultIds": []])
        for _ in 0..<100 where session.knownAdvancement["ccc-result:1002"] != .confirmed { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(session.knownAdvancement["ccc-result:1001"])
        XCTAssertEqual(session.knownAdvancement["ccc-result:1002"], .confirmed)
        XCTAssertEqual(session.selectedKey, first.round.key)
    }

    func testFilteredRecordSubsetNeverRecomputesQualificationFromPartialField() throws {
        let full = try snapshot((1...8).map { [$0 * 100] })
        let subset = CubingChinaLiveSnapshot(round: full.round, results: Array(full.results.prefix(3)))
        let presentation = CubingChinaLivePresentation.round(subset, rounds: [full.round], language: "en", advancementStates: [:])
        XCTAssertNil(presentation.results.first?.isAdvancing)
    }

    func testSelectionCancellationCannotInstallOldAdjacentRoster() async throws {
        let first = try snapshot((1...8).map { [$0 * 100] })
        let next = try snapshot([[100]], number: 2)
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        transport.holdResults(for: next.round.key)
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), transport: transport)
        session.start(); defer { session.stop(); transport.releaseHeldResults() }
        for _ in 0..<100 where transport.heldCount == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertGreaterThan(transport.heldCount, 0)
        session.select(next.round.key)
        transport.releaseHeldResults()
        for _ in 0..<100 where session.snapshot?.round.key != next.round.key { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(session.snapshot?.round.key, next.round.key)
        XCTAssertNil(session.nextParticipants(for: first.round), "A cancelled prior selection must not publish its roster")
    }

    func testInvalidRuleAndAverageOverflowRemainUnknown() throws {
        XCTAssertTrue(CompetitionAdvancementCalculation.states(try snapshot((1...8).map { [$0 * 100] }, type: "percent", level: 101), isFinal: false).isEmpty)
        let overflow = try snapshot([Array(repeating: Int.max, count: 5)] + (2...8).map { Array(repeating: $0 * 100, count: 5) }, format: "a")
        XCTAssertTrue(CompetitionAdvancementCalculation.states(overflow, isFinal: false).isEmpty)
    }

    func testWholeSecondAverageRoundingAboveTenMinutesPreservesClinchedRank() throws {
        let raw = try snapshot([[60000, 80000, 70035], [70000, 70000, 70000]] +
            (3...8).map { Array(repeating: $0 * 30000, count: 3) }, format: "m", level: 1)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(raw)) as! [String: Any]
        var rows = object["results"] as! [[String: Any]]
        // Both first means round to 700.00s. Best 600.00s breaks their mean tie.
        rows[0]["average"] = 70000; rows[1]["average"] = 70000
        for index in 2..<rows.count { rows[index]["average"] = (index + 1) * 30000 }
        object["results"] = rows
        let value = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(CompetitionAdvancementCalculation.states(value, isFinal: false)["ccc-result:1001"], .confirmed)
    }

    func testProductionRankingIndicatorsRenderGreenAndYellowInBothAppearances() async throws {
        let complete = try snapshot((1...8).map { [$0 * 100] })
        let incomplete = try snapshot([[100], [200], [300], [], [], [], [], []])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for dark in [false, true] {
            let view = VStack(spacing: 12) {
                CompetitionResultExperience(round: CubingChinaLivePresentation.round(complete, rounds: [complete.round], language: "en"), languageCode: "en", cardState: CompetitionResultCardState())
                CompetitionResultExperience(round: CubingChinaLivePresentation.round(incomplete, rounds: [incomplete.round], language: "en"), languageCode: "en", cardState: CompetitionResultCardState())
            }.padding(12).environment(\.colorScheme, dark ? .dark : .light)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = UIHostingController(rootView: view)
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 250_000_000)
            window.layoutIfNeeded()
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: screenshot); attachment.name = "advancement-production-\(dark)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }
}
