import XCTest
import SwiftUI
import Vision
@testable import CubeFlow

@MainActor final class CubingChinaLiveProgressTests: XCTestCase {
    private func fixture(number: Int = 1, event: String = "333", status: String = "live",
                         attempts: [[Int]] = [[100], [200], [300], [400], [500], [600], [0], [0]],
                         level: Int = 3, type: String = "ranking", format: String = "1",
                         startedAt: String? = nil) throws -> CubingChinaLiveSnapshot {
        let id = (event == "333" ? 0 : 100) + number
        let round: [String: Any] = ["id": id, "competitionId": 100, "competitionRoundId": 200 + id,
            "revision": 1, "eventId": event, "roundNumber": number, "status": status,
            "startedAt": startedAt as Any? ?? NSNull(),
            "round": ["id": 200 + id, "format": format, "advancementCondition": ["type": type, "level": level]]]
        let rows = attempts.enumerated().map { index, scores -> [String: Any] in
            let positives = scores.filter { $0 > 0 }
            return ["id": id * 1000 + index + 1, "competitionId": 100, "competitionRoundId": 200 + id,
                "registrationId": index + 10, "userId": index + 100, "eventId": event, "roundNumber": number,
                "attempts": scores, "best": positives.min() ?? (scores.contains(-1) ? -1 : scores.contains(-2) ? -2 : 0),
                "average": format == "a" && scores.count == 5 && !scores.contains(0) ? scores[2] : 0,
                "position": positives.isEmpty ? NSNull() : (index + 1) as Any,
                "competitor": ["id": index + 100, "number": index + 1, "name": "Person \(index)"]]
        }
        return try JSONDecoder().decode(CubingChinaLiveSnapshot.self,
            from: JSONSerialization.data(withJSONObject: ["round": round, "results": rows]))
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Live state did not settle"); throw CubingChinaLiveError.disconnected
    }
    private func delta(_ value: CubingChinaLiveSnapshot) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        return ["round": object["round"]!, "upsertedResults": object["results"]!, "removedResultIds": []]
    }

    func testDefaultSelectionTracksProgressAndIsIndependentOfArrayOrder() throws {
        let done1 = try fixture(number: 1, status: "finished").round
        let done2 = try fixture(number: 2, status: "finished").round
        let live3 = try fixture(number: 3).round
        let future = try fixture(number: 4, status: "open").round
        for rounds in [[future, done1, live3, done2], [done2, live3, done1, future]] {
            XCTAssertEqual(CubingChinaLiveBootstrap.preferredRound(in: rounds), live3)
        }
        XCTAssertEqual(CubingChinaLiveBootstrap.preferredRound(in: [future, done1, done2]), done2)
        XCTAssertEqual(CubingChinaLiveBootstrap.preferredRound(in: [done2, done1]), done2)
        let open1 = try fixture(number: 1, status: "open").round
        XCTAssertEqual(CubingChinaLiveBootstrap.preferredRound(in: [future, open1]), open1)
        let other = try fixture(event: "222", startedAt: "2026-11-02T10:00:00Z").round
        XCTAssertEqual(CubingChinaLiveBootstrap.preferredRound(in: [future, done2, other]), other)
    }

    func testEmptyStatesUseRecordedAttemptSemanticsNotRosterLength() throws {
        for rows in [[], [[0], [0, 0]]] as [[[Int]]] {
            XCTAssertEqual(CubingChinaLivePresentation.resultsState(try fixture(status: "open", attempts: rows)), .notStarted)
            XCTAssertEqual(CubingChinaLivePresentation.resultsState(try fixture(attempts: rows)), .noResults)
        }
        for attempts in [[[100]], [[-1]], [[-2]], [[0, -1]]] {
            XCTAssertEqual(CubingChinaLivePresentation.resultsState(try fixture(status: "open", attempts: attempts)), .recorded)
        }
        XCTAssertEqual(CubingChinaLivePresentation.resultsState(try fixture(status: "open", attempts: [], startedAt: "2026-11-02T09:00:00Z")), .noResults)
    }

    func testRulesMetadataIsOnePublicReadAndUnknownDualPolicyCannotAuthorizeGuarantees() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CubingChinaHTTPFixture.self]
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let client = CubingChinaLiveHTTPClient(session: network)
        CubingChinaHTTPFixture.configure(Data(#"{"id":100,"type":"WCA","events":[{"eventId":"333","dualRounds":false},{"eventId":"222","dualRounds":true},{"eventId":"444"}]}"#.utf8))
        let rules = try await client.competitionRules(slug: "Safe-2026")
        XCTAssertTrue(rules.supportsIndependentAdvancement("333"))
        XCTAssertFalse(rules.supportsIndependentAdvancement("222"))
        XCTAssertFalse(rules.supportsIndependentAdvancement("444"))
        XCTAssertFalse(rules.supportsIndependentAdvancement("555"))
        let requests = CubingChinaHTTPFixture.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/competitions/Safe-2026")
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Cookie"))
    }

    func testWorstCaseGuaranteeAndPossibilityHaveDistinctEvidence() throws {
        let value = try fixture()
        let states = CompetitionAdvancementCalculation.assessments(value, isFinal: false, hasCompleteRoster: true)
        XCTAssertEqual(states["ccc-result:1001"], .guaranteed) // at worst third
        XCTAssertEqual(states["ccc-result:1002"], .possible) // at worst fourth
        XCTAssertEqual(states["ccc-result:1006"], .eliminated)
        let unknown = CompetitionAdvancementCalculation.assessments(value, isFinal: false, hasCompleteRoster: false)
        XCTAssertEqual(unknown["ccc-result:1001"], .possible)
        XCTAssertFalse(unknown.values.contains(.guaranteed))
        let next = try fixture(number: 2, status: "open", attempts: [])
        let missing = CubingChinaLivePresentation.advancement(value, rounds: [value.round, next.round], hasCompleteRoster: true)
        XCTAssertEqual(missing["ccc-result:1002"], .possible, "A missing next-round request must not erase yellow")
        let withRoster = CubingChinaLivePresentation.assessments(value, rounds: [value.round, next.round],
            nextParticipants: [value.results[5].userId], hasCompleteRoster: true, supportsIndependentAdvancement: true)
        XCTAssertEqual(withRoster["ccc-result:1006"], .authoritative)
        XCTAssertEqual(withRoster["ccc-result:1002"], .possible)
    }

    func testFortyCompetitorExamplesAndExhaustiveSmallRemainingField() throws {
        let rows = (1...37).map { [$0 * 100] } + Array(repeating: [0], count: 3)
        let forty = try fixture(attempts: rows, level: 12)
        let states = CompetitionAdvancementCalculation.assessments(forty, isFinal: false, hasCompleteRoster: true)
        XCTAssertEqual(states["ccc-result:1005"], .guaranteed)
        let fiveRemaining = try fixture(attempts: (1...35).map { [$0 * 100] } + Array(repeating: [0], count: 5), level: 12)
        XCTAssertEqual(CompetitionAdvancementCalculation.assessments(fiveRemaining, isFinal: false, hasCompleteRoster: true)["ccc-result:1010"], .possible)
        let small = try fixture()
        let certain = CompetitionAdvancementCalculation.assessments(small, isFinal: false, hasCompleteRoster: true)
        for a in [-2, -1, 1, 100, 10000] {
            for b in [-2, -1, 1, 100, 10000] {
                let realized = [100, 200, 300, 400, 500, 600, a, b]
                for index in 0..<6 where certain["ccc-result:\(1001 + index)"] == .guaranteed {
                    let tiedOrBetter = realized.filter { $0 > 0 && $0 <= realized[index] }.count
                    XCTAssertLessThanOrEqual(tiedOrBetter, 3)
                }
            }
        }
        let percent = try fixture(attempts: (1...8).map { [$0 * 100] }, level: 25, type: "percent")
        let percentage = CompetitionAdvancementCalculation.states(percent, isFinal: false)
        XCTAssertEqual(percentage.count, 2); XCTAssertEqual(percentage["ccc-result:1002"], .confirmed)
    }

    func testDelayedAdjacentResponseCannotOverwriteEqualRevisionSSECorrection() async throws {
        let first = try fixture(), next = try fixture(number: 2, status: "open", attempts: [])
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        transport.holdResults(for: first.round.key)
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), transport: transport)
        session.select(next.round.key, explicitlyRequested: true); session.start()
        defer { session.stop(); transport.releaseHeldResults() }
        try await wait { transport.heldCount > 0 && session.snapshot?.round.key == next.round.key }
        let corrected = try fixture(attempts: [[900], [200], [300], [400], [500], [600], [0], [0]])
        transport.setSnapshot(corrected)
        try transport.emit("result.updated", payload: delta(corrected))
        try await wait { transport.heldCount > 1 }
        transport.releaseHeldResults()
        try await wait { session.roundAdvancement[first.round.key.selectionID] != nil }
        XCTAssertFalse(session.inferredParticipants(for: next.round).contains { $0.id == 100 })
        XCTAssertEqual(session.selectedKey, next.round.key)
    }

    func testTiesPercentageCutoffAndDNFStayConservative() throws {
        let tied = try fixture(attempts: [[100], [100], [100], [400], [500], [600], [700], [800]], level: 2)
        let ties = CompetitionAdvancementCalculation.assessments(tied, isFinal: false, hasCompleteRoster: true)
        XCTAssertFalse(ties.values.contains(.guaranteed))
        let percentage = try fixture(type: "percent")
        XCTAssertTrue(CompetitionAdvancementCalculation.states(percentage, isFinal: false).isEmpty) // 3% => zero places
        let dnf = try fixture(attempts: [[-1], [-2], [100], [200], [300], [400], [0], [0]])
        XCTAssertEqual(CompetitionAdvancementCalculation.assessments(dnf, isFinal: false, hasCompleteRoster: true)["ccc-result:1001"], .eliminated)
        let dual = CubingChinaLiveCompetitionRules(id: .init(100), type: "WCA", events: [.init(eventId: "333", dualRounds: true)])
        XCTAssertFalse(dual.supportsIndependentAdvancement("333"))
        let states = CubingChinaLivePresentation.assessments(tied, rounds: [tied.round], hasCompleteRoster: true,
            supportsIndependentAdvancement: dual.supportsIndependentAdvancement("333"))
        XCTAssertTrue(states.isEmpty)
    }

    func testNextPreviewIsIdentityOnlyAndCorrectsWithoutManualSelectionOfSource() async throws {
        let first = try fixture(), next = try fixture(number: 2, status: "open", attempts: [])
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), transport: transport)
        session.select(next.round.key)
        session.start(); defer { session.stop() }
        try await wait { session.snapshot?.round.key == next.round.key && session.inferredParticipants(for: next.round).count == 1 }
        XCTAssertEqual(session.inferredParticipants(for: next.round).first?.id, 100)
        XCTAssertEqual(session.snapshot?.results.count, 0, "Local preview must not mutate official result ownership")
        let inferred = try XCTUnwrap(session.inferredParticipants(for: next.round).first)
        XCTAssertEqual(inferred.sourceRound, first.round.key)
        XCTAssertNil(session.inferredParticipants(for: next.round).first { $0.id == 101 }, "Yellow is not an inferred entrant")
        var corrected = try fixture(attempts: [[900], [200], [300], [400], [500], [600], [0], [0]])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(corrected)) as! [String: Any]
        var metadata = object["round"] as! [String: Any]; metadata["revision"] = 2; object["round"] = metadata
        corrected = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try transport.emit("result.updated", payload: delta(corrected))
        try await wait { !session.inferredParticipants(for: next.round).contains { $0.id == inferred.id } }
        XCTAssertEqual(session.selectedKey, next.round.key)
        session.select(first.round.key)
        try await wait { session.snapshot?.round.key == first.round.key }
        XCTAssertTrue(session.inferredParticipants(for: first.round).isEmpty)
    }

    func testAuthoritativeArrivalReconcilesPreviewAndMetadataDoesNotJumpSelection() async throws {
        let first = try fixture(), next = try fixture(number: 2, status: "open", attempts: [])
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [next])
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), transport: transport)
        session.select(next.round.key, explicitlyRequested: true); session.start(); defer { session.stop() }
        try await wait { !session.inferredParticipants(for: next.round).isEmpty }
        var authoritative = try fixture(number: 2, status: "open", attempts: [[0]])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(authoritative)) as! [String: Any]
        var metadata = object["round"] as! [String: Any]; metadata["revision"] = 2; object["round"] = metadata
        authoritative = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try transport.emit("round.competitor.joined", payload: delta(authoritative))
        try await wait { session.snapshot?.results.count == 1 }
        XCTAssertTrue(session.inferredParticipants(for: authoritative.round).isEmpty)
        XCTAssertFalse(session.snapshot?.results.first?.hasRecordedAttempts ?? true)
        XCTAssertEqual(session.selectedKey, next.round.key)
        var update = try delta(first)
        var updatedRound = update["round"] as! [String: Any]
        updatedRound["revision"] = 2; updatedRound["status"] = "finished"; update["round"] = updatedRound
        try transport.emit("round.updated", payload: update)
        try await wait { session.rounds.first { $0.key == first.round.key }?.revision == 2 }
        XCTAssertEqual(session.selectedKey, next.round.key, "SSE progress changes must not navigate away from an explicit selection")
        XCTAssertEqual(session.snapshot?.round.key, next.round.key)
        let bridge = CompetitionCubingLiveSession()
        bridge.configure(with: CubingChinaLivePresentation.content(try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, next.round]), language: "en"), transport: transport)
        bridge.applyInitialRoundOption(next.round.key.selectionID)
        XCTAssertEqual(bridge.modernSession?.selectedKey, next.round.key, "A deep link is explicit, even before start")
    }

    func testMountedEmptyRoundRetainsParticipantsWithoutAnEmptyScoreTable() async throws {
        let value = try fixture(status: "open", attempts: [[0], [0]])
        let transport = FakeCubingChinaTransport(snapshot: value)
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round]), transport: transport)
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: ScrollView {
            CubingChinaUnifiedLiveContent(session: session, extras: CubingChinaLiveExtrasStore(), card: CompetitionResultCardState(),
                roundSelection: .constant(value.round.key.selectionID), language: "en", loadCompetitor: { _ in nil }) { EmptyView() }
        }.padding(16))
        window.makeKeyAndVisible(); defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 100_000_000); window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
        XCTAssertTrue(text.contains("Not Started"), text)
        XCTAssertTrue(text.contains("Person"), text)
        XCTAssertFalse(text.contains("Average"), text)
        XCTAssertFalse(text.contains("Best"), text)
        let attachment = XCTAttachment(image: image); attachment.name = "CubingChina unstarted round retains roster without scores"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
