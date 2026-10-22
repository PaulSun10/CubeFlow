import XCTest
@testable import CubeFlow

@MainActor
final class CubingChinaModernLiveTests: XCTestCase {
    private func snapshot(_ bytes: Data = CubingChinaModernLiveFixtures.beijing) throws -> CubingChinaLiveSnapshot {
        try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: bytes).validated()
    }
    private func revised(_ value: CubingChinaLiveSnapshot, revision: Int) throws -> CubingChinaLiveSnapshot {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        var round = object["round"] as! [String: Any]; round["revision"] = revision; object["round"] = round
        return try snapshot(JSONSerialization.data(withJSONObject: object))
    }

    func testBothPublicArchivesDecodeWithoutMixingIdentityDomains() throws {
        let beijing = try snapshot(), guangzhou = try snapshot(CubingChinaModernLiveFixtures.guangzhou)
        XCTAssertEqual(beijing.results.count, 17); XCTAssertEqual(guangzhou.results.count, 40)
        XCTAssertEqual(beijing.round.id.rawValue, 9518); XCTAssertEqual(beijing.round.competitionRoundId.rawValue, 12026)
        XCTAssertEqual(beijing.round.competitionId.rawValue, 1602); XCTAssertEqual(beijing.round.key.selectionID, "777|2")
        XCTAssertEqual(guangzhou.round.key.selectionID, "333|3"); XCTAssertEqual(guangzhou.round.revision, 109)
        XCTAssertEqual(beijing.rankedResults.first?.competitor?.number, 112)
        XCTAssertEqual(beijing.rankedResults.first?.competitor?.wcaId, "2019TARA09")
        XCTAssertEqual(beijing.rankedResults.first?.singleBadge, "WR")
        XCTAssertEqual(beijing.rankedResults.first?.averageBadge, "WR")
        XCTAssertNil(guangzhou.rankedResults.first?.averageBadge, "A world-rank marker is not a record")
        let presentation = CubingChinaLivePresentation.round(beijing, rounds: [beijing.round], language: "en")
        XCTAssertEqual(presentation.results.map(\.ranking), beijing.rankedResults.map(\.position))
        XCTAssertEqual(presentation.results.first?.average, 9593)
        XCTAssertNil(presentation.results.first?.personID)
        XCTAssertTrue(presentation.results.first?.isAdvancing == true, "Completed final podium uses the existing WCA Live green semantics")
        XCTAssertNil(presentation.results.last?.isAdvancing)
        XCTAssertTrue(presentation.id.hasPrefix("ccc-round:"))
    }

    func testModernCanonicalTargetAndLegacyCacheCompatibility() throws {
        let value = try snapshot()
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let content = CubingChinaLivePresentation.content(bootstrap, language: "en")
        var target = CompetitionWCALiveResultDeepLink(roundID: "unrelated-WCA-id", personID: nil, personWCAID: nil,
            eventID: "777", roundNumber: 2)
        XCTAssertEqual(content.targetRound(for: target)?.id, "777|2")
        target.roundNumber = 1; XCTAssertNil(content.targetRound(for: target))
        var bytes = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as! [String: Any]
        bytes.removeValue(forKey: "modern")
        XCTAssertNil(try JSONDecoder().decode(CompetitionLiveContent.self,
            from: JSONSerialization.data(withJSONObject: bytes)).modern)
        bytes["modern"] = ["slug": "Beijing-Autumn-Rivalry-2026", "competitionID": 1602, "rounds": []]
        XCTAssertThrowsError(try JSONDecoder().decode(CompetitionLiveContent.self,
            from: JSONSerialization.data(withJSONObject: bytes)))
    }

    func testSnapshotDeltaStaleEqualNextRemovalAndGapRecovery() throws {
        let original = try snapshot(); var state = CubingChinaLiveRoundState(round: original.round)
        XCTAssertTrue(try state.install(original))
        let first = original.results[0]
        XCTAssertFalse(try state.apply(.init(round: original.round, upsertedResults: [first], removedResultIds: [])))
        XCTAssertEqual(state.snapshot?.results.count, 17)
        let next = try revised(original, revision: 46)
        XCTAssertFalse(try state.apply(.init(round: next.round, upsertedResults: [], removedResultIds: [first.id])))
        XCTAssertEqual(state.snapshot?.results.count, 16)
        XCTAssertFalse(try state.apply(.init(round: original.round, upsertedResults: [first], removedResultIds: [])))
        XCTAssertEqual(state.snapshot?.results.count, 16)
        let gap = try revised(original, revision: 49)
        XCTAssertTrue(try state.apply(.init(round: gap.round, upsertedResults: [first], removedResultIds: [])))
        XCTAssertFalse(try state.install(next)); XCTAssertEqual(state.minimumRevision, 49)
        XCTAssertTrue(try state.install(gap)); XCTAssertEqual(state.snapshot?.round.revision, 49)
        XCTAssertThrowsError(try state.install(snapshot(CubingChinaModernLiveFixtures.guangzhou)))
    }

    func testEmptyActiveSnapshotIsSupportedAndBadIdentitiesRejected() throws {
        var object = try JSONSerialization.jsonObject(with: CubingChinaModernLiveFixtures.beijing) as! [String: Any]
        var round = object["round"] as! [String: Any]; round["status"] = "live"; object["round"] = round
        let value = try snapshot(JSONSerialization.data(withJSONObject: object))
        let empty = CubingChinaLiveSnapshot(round: value.round, results: [])
        XCTAssertEqual(try empty.validated().results.count, 0)
        XCTAssertFalse(empty.round.isFinished)
        XCTAssertThrowsError(try CubingChinaLiveSnapshot(round: value.round, results: [value.results[0], value.results[0]]).validated())
        XCTAssertThrowsError(try CubingChinaLiveSnapshot(round: value.round,
            results: snapshot(CubingChinaModernLiveFixtures.guangzhou).results).validated())
        XCTAssertThrowsError(try CubingChinaLiveBootstrap.make(slug: "../bad", rounds: [value.round]))
    }

    func testSSEFramingEveryChunkBoundaryMultilineUTF8CRLFAndHeartbeat() throws {
        let text = "\u{FEFF}: comment\r\nevent: message.created\r\nid: 17\r\ndata: {\"a\":\r\ndata: \"\u{4F60}\u{597D}\"}\r\n\r\nevent: heartbeat\ndata: {}\n\n"
        let bytes = Array(text.utf8)
        for chunkSize in 1...bytes.count {
            var parser = CubingChinaSSEParser(), frames: [CubingChinaSSEFrame] = []
            for start in stride(from: 0, to: bytes.count, by: chunkSize) {
                frames += try parser.append(bytes[start..<min(start + chunkSize, bytes.count)])
            }
            XCTAssertEqual(frames.count, 2)
            XCTAssertEqual(frames[0].event, "message.created"); XCTAssertEqual(frames[0].id, "17")
            XCTAssertEqual(frames[0].data, "{\"a\":\n\"\u{4F60}\u{597D}\"}")
            XCTAssertEqual(frames[1].event, "heartbeat")
        }
        var parser = CubingChinaSSEParser(); parser.limit = 10
        XCTAssertThrowsError(try parser.append(Array("data: excessively-large".utf8)))
        var unfinished = CubingChinaSSEParser()
        XCTAssertTrue(try unfinished.append(Array("data: incomplete\n".utf8)).isEmpty)
    }

    func testExactWCAIdentityNoNameCaseOrMissingIDInference() {
        XCTAssertTrue(CompetitionPersonalIdentity.matches(signedInWCAID: "2019TARA09", competitorWCAID: "2019TARA09"))
        let candidates: [String?] = [nil, "", "2019tara09", "2019TARA08", " 2019TARA09", "2019TARA09\n", "Timofei Tarasenko"]
        for candidate in candidates {
            XCTAssertFalse(CompetitionPersonalIdentity.matches(signedInWCAID: "2019TARA09", competitorWCAID: candidate))
            XCTAssertFalse(CompetitionPersonalIdentity.matches(signedInWCAID: candidate, competitorWCAID: "2019TARA09"))
        }
    }

    func testRecordNormalizationKeepsRegionalProvenanceAndHighestLevel() throws {
        for (wire, expected) in [("WR", "WR"), ("AsR", "CR"), ("NR", "NR")] {
            var object = try JSONSerialization.jsonObject(with: CubingChinaModernLiveFixtures.beijing) as! [String: Any]
            var results = object["results"] as! [[String: Any]]
            results[0]["regionalSingleRecord"] = wire
            results[0]["regionalAverageRecord"] = NSNull()
            results[0]["rankSingleMarker"] = "WR1"
            object["results"] = results
            let result = try snapshot(JSONSerialization.data(withJSONObject: object)).results[0]
            XCTAssertEqual(result.singleBadge, expected)
            XCTAssertNil(result.averageBadge)
        }
        XCTAssertEqual(PublishedCompetitionResult.highestBadge(["NR", "CR", "WR"]), "WR")
        XCTAssertEqual(PublishedCompetitionResult.highestBadge(["NR", "CR"]), "CR")
        XCTAssertNil(PublishedCompetitionResult.recordBadge("WR1"))
    }

    func testSessionResyncReconnectChatDeletionAndCancellation() async throws {
        let value = try snapshot()
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let transport = FakeCubingChinaTransport(snapshot: value)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport, pause: { _ in try Task.checkCancellation() })
        session.start()
        await eventually { session.snapshot != nil && !session.isLoadingMessages }
        try transport.emit("message.created", payload: ["id": 7, "competitionId": 1602,
            "content": "Read-only", "createdAt": "2026-10-11T10:00:00Z", "user": ["name": "Fixture"]])
        await eventually { session.messages.count == 1 }
        try transport.emit("message.deleted", payload: ["id": 7])
        await eventually { session.messages.isEmpty }
        transport.disconnect()
        await eventually { transport.connectionCount >= 2 }
        await eventually { transport.resultRequests >= 2 }
        session.stop()
        await eventually { transport.cancelCount >= 1 }
        let before = session.snapshot
        try transport.emit("heartbeat", payload: [:])
        XCTAssertEqual(session.snapshot, before)
        XCTAssertFalse(session.isLoadingResults); XCTAssertFalse(session.isLoadingMessages)
    }

    func testReconnectAttemptsAreBounded() async throws {
        let value = try snapshot()
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let transport = FakeCubingChinaTransport(snapshot: value, failsConnections: true)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport, pause: { _ in try Task.checkCancellation() })
        session.start()
        await eventually { transport.connectionCount == 5 }
        try await Task.sleep(nanoseconds: 20_000_000)
        let connections = transport.connections()
        XCTAssertEqual(connections, 5)
        XCTAssertNotNil(session.connectionError)
        session.stop()
    }

    func testSelectionRejectsLateSnapshotAndNeverFetchesUnselectedRounds() async throws {
        let first = try snapshot()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        var round = object["round"] as! [String: Any]
        round["id"] = 9519; round["competitionRoundId"] = 12027; round["eventId"] = "666"; round["roundNumber"] = 1
        var rules = round["round"] as! [String: Any]; rules["id"] = 12027; round["round"] = rules
        object["round"] = round; object["results"] = [[String: Any]]()
        let second = try snapshot(JSONSerialization.data(withJSONObject: object))
        let transport = FakeCubingChinaTransport(snapshot: first, additional: [second])
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round, second.round])
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        transport.holdResults(for: first.round.key)
        session.start()
        await eventually { transport.heldCount > 0 }
        session.select(second.round.key)
        await eventually { session.snapshot?.round.key == second.round.key }
        transport.releaseHeldResults()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(session.snapshot?.round.key, second.round.key)
        XCTAssertTrue(transport.requestedKeys.allSatisfy { $0 == first.round.key || $0 == second.round.key })
        XCTAssertEqual(transport.connectionCount, 1)
        session.stop()
    }

    func testGapResnapshotAndRapidResumeDoNotCancelReplacementConnection() async throws {
        let original = try snapshot(), replacement = try revised(original, revision: 49)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [original.round])
        let transport = FakeCubingChinaTransport(snapshot: original)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        session.start()
        await eventually { session.snapshot != nil && transport.resultRequests >= 2 && !session.isLoadingMessages }
        transport.setSnapshot(replacement)
        let delta = CubingChinaLiveDelta(round: replacement.round, upsertedResults: [], removedResultIds: [])
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(delta)) as! [String: Any]
        try transport.emit("result.updated", payload: payload)
        await eventually { session.snapshot?.round.revision == 49 }
        XCTAssertEqual(session.snapshot?.results.count, original.results.count)
        session.stop(); session.start()
        await eventually { transport.connectionCount == 2 && !session.isLoadingMessages }
        try transport.emit("heartbeat", payload: [:])
        await eventually { session.viewers == 2 }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(transport.connectionCount, 2, "Old cancellation must not finish the replacement stream")
        XCTAssertTrue(transport.requestedKeys.allSatisfy { $0 == original.round.key })
        session.stop()
    }

    func testVerifiedModernBootstrapWebsiteFallbackAndIdentityGate() async throws {
        let value = try snapshot(), slug = "Beijing-Autumn-Rivalry-2026"
        let table: [Any] = [["competition:\(slug)": 1, "live-records:\(slug)": 6],
            ["alias": 2, "live": 3, "wcaCompetitionId": 4, "id": 5], slug, true, "BeijingAutumnRivalry2026", 1602,
            [7], ["eventId": 8, "roundNumber": 9], "777", 2]
        let html = "<script id=\"__NUXT_DATA__\" type=\"application/json\">\(String(decoding: try JSONSerialization.data(withJSONObject: table), as: UTF8.self))</script>"
        let transport = FakeCubingChinaTransport(snapshot: value)
        let native = await CompetitionService.resolveCubingChinaLive(html: html, slug: slug,
            expectedWCAID: "BeijingAutumnRivalry2026", language: "en", transport: transport)
        XCTAssertEqual(native?.liveContent?.modern?.competitionID, value.round.competitionId)
        XCTAssertNotNil(native?.cubingChinaLiveWebsite)
        XCTAssertEqual(transport.resultRequests, 0, "Discovery loads rounds, never all results")
        var activeTable = table; activeTable[6] = [Int]()
        let activeHTML = "<script id=\"__NUXT_DATA__\" type=\"application/json\">\(String(decoding: try JSONSerialization.data(withJSONObject: activeTable), as: UTF8.self))</script>"
        let active = await CompetitionService.resolveCubingChinaLive(html: activeHTML, slug: slug,
            expectedWCAID: "BeijingAutumnRivalry2026", language: "en", transport: transport)
        XCTAssertNotNil(active?.liveContent?.modern, "Native rounds do not require an existing record-bearing SSR archive")
        XCTAssertNil(active?.cubingChinaLiveWebsite)
        let fallback = await CompetitionService.resolveCubingChinaLive(html: html, slug: slug,
            expectedWCAID: "BeijingAutumnRivalry2026", language: "en",
            transport: FakeCubingChinaTransport(snapshot: value, failsRoundList: true))
        XCTAssertNil(fallback?.liveContent); XCTAssertEqual(fallback?.liveAvailability, .available)
        XCTAssertEqual(fallback?.cubingChinaLiveWebsite?.rounds.first?.eventID, "777")
        let wrong = await CompetitionService.resolveCubingChinaLive(html: html, slug: slug,
            expectedWCAID: "Wrong2026", language: "en", transport: transport)
        XCTAssertNil(wrong)
    }

    func testReadOnlyChatFailureAndCompetitorNumberIdentityGate() async throws {
        let value = try snapshot()
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let transport = FakeCubingChinaTransport(snapshot: value, failsMessages: true)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        session.start()
        await eventually { session.chatError != nil && session.snapshot != nil }
        XCTAssertTrue(session.messages.isEmpty); XCTAssertFalse(session.isLoadingMessages)
        let own = await session.competitorResults(number: 112)
        XCTAssertEqual(own?.count, 1)
        XCTAssertEqual(own?.first?.competitor?.wcaId, "2019TARA09")
        let missing = await session.competitorResults(number: 99999)
        XCTAssertNil(missing)
        session.stop()
    }

    private func eventually(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Condition not reached", file: file, line: line)
    }
}

nonisolated final class FakeCubingChinaTransport: CubingChinaLiveTransport, @unchecked Sendable {
    let value: CubingChinaLiveSnapshot
    let failsConnections: Bool
    let failsRoundList: Bool
    let failsMessages: Bool
    private let lock = NSLock()
    private var connectionCounter = 0
    private var cancellationCounter = 0
    private var requestCounter = 0
    private var values: [CubingChinaLiveRoundKey: CubingChinaLiveSnapshot]
    private var keys: [CubingChinaLiveRoundKey] = []
    private var heldKey: CubingChinaLiveRoundKey?
    private var held: [(CheckedContinuation<CubingChinaLiveSnapshot, Error>, CubingChinaLiveSnapshot)] = []
    private var continuation: AsyncThrowingStream<CubingChinaSSEFrame, Error>.Continuation?
    var connectionCount: Int { lock.withLock { connectionCounter } }
    var cancelCount: Int { lock.withLock { cancellationCounter } }
    var resultRequests: Int { lock.withLock { requestCounter } }
    var requestedKeys: [CubingChinaLiveRoundKey] { lock.withLock { keys } }
    var heldCount: Int { lock.withLock { held.count } }
    init(snapshot: CubingChinaLiveSnapshot, failsConnections: Bool = false, additional: [CubingChinaLiveSnapshot] = [],
         failsRoundList: Bool = false, failsMessages: Bool = false) {
        value = snapshot; self.failsConnections = failsConnections
        self.failsRoundList = failsRoundList; self.failsMessages = failsMessages
        values = Dictionary(uniqueKeysWithValues: ([snapshot] + additional).map { ($0.round.key, $0) })
    }
    func rounds(slug: String) async throws -> [CubingChinaLiveRound] {
        if failsRoundList { throw CubingChinaLiveError.http(503) }
        return lock.withLock { values.values.map(\.round).sorted { $0.id.rawValue < $1.id.rawValue } }
    }
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot {
        try await withCheckedThrowingContinuation { incoming in
            let immediate = lock.withLock { () -> CubingChinaLiveSnapshot? in
                requestCounter += 1; keys.append(key)
                let snapshot = values[key] ?? value
                if heldKey == key { held.append((incoming, snapshot)); return nil }
                return snapshot
            }
            if let immediate { incoming.resume(returning: immediate) }
        }
    }
    func messages(slug: String) async throws -> [CubingChinaLiveMessage] {
        if failsMessages { throw CubingChinaLiveError.http(403) }
        return []
    }
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult] {
        value.results.filter { $0.competitor?.number == number }
    }
    func setSnapshot(_ snapshot: CubingChinaLiveSnapshot) { lock.withLock { values[snapshot.round.key] = snapshot } }
    func holdResults(for key: CubingChinaLiveRoundKey) { lock.withLock { heldKey = key } }
    func releaseHeldResults() {
        let pending = lock.withLock { let pending = held; held = []; heldKey = nil; return pending }
        for (continuation, snapshot) in pending { continuation.resume(returning: snapshot) }
    }
    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection {
        lock.withLock { connectionCounter += 1 }
        if failsConnections { throw CubingChinaLiveError.disconnected }
        let frames = AsyncThrowingStream<CubingChinaSSEFrame, Error> { incoming in lock.withLock { continuation = incoming } }
        let current = lock.withLock { continuation }
        return CubingChinaLiveConnection(frames: frames, cancel: { current?.finish(); self.cancel() })
    }
    func cancel() { lock.withLock { cancellationCounter += 1 } }
    func disconnect() { lock.withLock { continuation }?.finish(throwing: CubingChinaLiveError.disconnected) }
    func connections() -> Int { connectionCount }
    func emit(_ type: String, payload: [String: Any]) throws {
        let bytes = try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload, "viewers": 2])
        lock.withLock { continuation }?.yield(CubingChinaSSEFrame(event: type, id: nil, data: String(decoding: bytes, as: UTF8.self)))
    }
}
