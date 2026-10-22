import XCTest
import Combine
@testable import CubeFlow

private actor EmptyCacheRecordSummary: CubingChinaLiveExtrasTransport {
    func records(slug: String) async throws -> [CubingChinaLiveResult] { [] }
    func podiums(slug: String) async throws -> [CubingChinaLivePodium] { [] }
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank] { [] }
}

private actor CompetitorCacheTransport: CubingChinaLiveTransport {
    let core: FakeCubingChinaTransport
    private(set) var competitorCalls = 0
    init(_ core: FakeCubingChinaTransport) { self.core = core }
    func rounds(slug: String) async throws -> [CubingChinaLiveRound] { try await core.rounds(slug: slug) }
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot { try await core.results(slug: slug, key: key) }
    func messages(slug: String) async throws -> [CubingChinaLiveMessage] { [] }
    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection { try await core.events(slug: slug, viewerID: viewerID) }
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult] {
        competitorCalls += 1
        let values = try await core.competitorResults(slug: slug, number: number)
        try await Task.sleep(nanoseconds: 100_000_000)
        return values
    }
}

@MainActor final class CubingLiveSessionCacheTests: XCTestCase {
    func testIdenticalReconnectRevalidationDoesNotRepublishCanonicalArraysOrBadges() async throws {
        let a = try snapshot()
        let (session, core) = try setup(a, [])
        session.start(); defer { session.stop() }
        try await wait { session.hasCurrentSnapshot && core.connectionCount == 1 && !session.isLoadingResults }
        var snapshots = 0, metadata = 0, badges = 0, messages = 0
        let observations = [session.$snapshot.dropFirst().sink { _ in snapshots += 1 },
            session.$rounds.dropFirst().sink { _ in metadata += 1 },
            session.$knownRoundBadges.dropFirst().sink { _ in badges += 1 },
            session.$messages.dropFirst().sink { _ in messages += 1 }]
        let before = core.resultRequests
        session.retry()
        try await wait { session.hasCurrentSnapshot && core.connectionCount == 2 && core.resultRequests > before && !session.isLoadingResults }
        XCTAssertEqual(snapshots, 0); XCTAssertEqual(metadata, 0)
        XCTAssertEqual(badges, 0); XCTAssertEqual(messages, 0)
        withExtendedLifetime(observations) {}
    }
    private func snapshot(event: String = "777", offset: Int = 0, revision: Int = 45, record: Bool = true) throws -> CubingChinaLiveSnapshot {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: CubingChinaModernLiveFixtures.beijing) as? [String: Any])
        var round = json["round"] as! [String: Any], rules = round["round"] as! [String: Any]
        let number = offset == 0 ? 2 : 1
        round["id"] = 9518 + offset; round["competitionRoundId"] = 12026 + offset
        round["eventId"] = event; round["roundNumber"] = number; round["revision"] = revision
        round["status"] = offset == 0 ? "live" : "finished"
        rules["id"] = 12026 + offset; round["round"] = rules; json["round"] = round
        var rows = json["results"] as! [[String: Any]]
        rows = [rows[0]]
        rows[0]["id"] = 410250 + offset; rows[0]["competitionRoundId"] = 12026 + offset
        rows[0]["eventId"] = event; rows[0]["roundNumber"] = number
        if !record {
            for key in ["regionalSingleRecord", "regionalAverageRecord", "personalSingleRecord", "personalAverageRecord"] { rows[0][key] = "" }
        }
        json["results"] = rows
        return try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: json)).validated()
    }
    private func setup(_ first: CubingChinaLiveSnapshot, _ others: [CubingChinaLiveSnapshot]) throws -> (CubingChinaModernLiveSession, FakeCubingChinaTransport) {
        let core = FakeCubingChinaTransport(snapshot: first, additional: others)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [first.round] + others.map(\.round))
        return (.init(bootstrap: bootstrap, transport: core, pause: { _ in }), core)
    }
    private func wait(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for authoritative session state")
    }
    private func emit(_ value: CubingChinaLiveSnapshot, via core: FakeCubingChinaTransport, removed: [CubingChinaLiveID<CubingChinaIDKind.Result>] = []) throws {
        let delta = CubingChinaLiveDelta(round: value.round, upsertedResults: value.results, removedResultIds: removed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(delta)) as? [String: Any])
        try core.emit("result.updated", payload: json)
    }
    private func load(_ session: CubingChinaModernLiveSession, _ value: CubingChinaLiveSnapshot) async throws {
        session.select(value.round.key)
        try await wait { session.snapshot?.round == value.round }
    }

    func testVisitedRoundReturnsSynchronouslyWithoutAnotherFetchOrSubscription() async throws {
        let a = try snapshot(), b = try snapshot(event: "666", offset: 100)
        let (session, core) = try setup(a, [b])
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        try await load(session, b)
        let requests = core.resultRequests
        session.select(a.round.key)
        XCTAssertEqual(session.snapshot?.round.key, a.round.key)
        XCTAssertEqual(session.snapshot?.results, a.results)
        XCTAssertEqual(core.resultRequests, requests)
        XCTAssertEqual(core.connectionCount, 1)
    }
    func testOldFullSnapshotBadgeCannotOverrideNewSummaryAfterAuthorityInvalidation() async throws {
        let a = try snapshot(), corrected = try snapshot(record: false)
        let (session, core) = try setup(a, [])
        session.start(); defer { core.releaseHeldResults(); session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        let summary = CubingChinaLiveExtrasStore()
        summary.refresh(session.bootstrap, transport: EmptyCacheRecordSummary())
        try await wait { !summary.isLoading }
        XCTAssertEqual(session.roundRecordTags(in: summary)[a.round.key.selectionID], "WR")
        core.setSnapshot(corrected); core.holdResults(for: a.round.key)
        let before = session.aggregateRefreshID
        try core.emit("unknown.provider.event", payload: [:])
        try await wait { session.aggregateRefreshID > before && core.heldCount > 0 }
        XCTAssertNil(session.roundRecordTags(in: summary)[a.round.key.selectionID],
            "A full snapshot from an invalidated stream epoch cannot resurrect its old WR")
        core.releaseHeldResults()
        try await wait { session.snapshot?.results.first?.singleIndicator == nil && session.snapshot != nil }
        XCTAssertNil(session.roundRecordTags(in: summary)[a.round.key.selectionID])
        summary.stop()
    }
    func testUnselectedEqualRevisionCorrectionsAndDeletionUpdateCachedRound() async throws {
        let a = try snapshot(), b = try snapshot(event: "666", offset: 100)
        let corrected = try snapshot(event: "666", offset: 100, record: false)
        let (session, core) = try setup(a, [b])
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        try await load(session, b); try await load(session, a)
        let previous = session.aggregateRefreshID, requests = core.resultRequests
        try emit(corrected, via: core)
        try await wait { session.aggregateRefreshID > previous }
        session.select(b.round.key)
        XCTAssertNil(session.snapshot?.results.first?.singleIndicator)
        XCTAssertNil(session.snapshot?.results.first?.averageIndicator)
        XCTAssertEqual(core.resultRequests, requests)
        try await load(session, a)
        let next = session.aggregateRefreshID
        try emit(.init(round: b.round, results: []), via: core, removed: b.results.map(\.id))
        try await wait { session.aggregateRefreshID > next }
        session.select(b.round.key)
        XCTAssertEqual(session.snapshot?.results.count, 0, "Deleted result must not return from the visited-round cache")
        XCTAssertEqual(core.resultRequests, requests)
    }
    func testRevisionGapRejectsWarmCacheAndFetchesAuthoritativeSnapshot() async throws {
        let a = try snapshot(), b = try snapshot(event: "666", offset: 100)
        let next = try snapshot(event: "666", offset: 100, revision: 48, record: false)
        let (session, core) = try setup(a, [b])
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        try await load(session, b); try await load(session, a)
        core.setSnapshot(next); try emit(next, via: core)
        try await wait { session.rounds.contains(next.round) }
        let count = core.resultRequests
        session.select(b.round.key)
        XCTAssertNil(session.snapshot, "Gapped cached data must not be called current")
        try await wait { session.snapshot?.round == next.round }
        XCTAssertGreaterThan(core.resultRequests, count)
        XCTAssertNil(session.snapshot?.results.first?.singleIndicator)
    }
    func testReconnectAndUnknownEventsInvalidateVisitedRoundAuthority() async throws {
        let a = try snapshot(), b = try snapshot(event: "666", offset: 100)
        let (session, core) = try setup(a, [b])
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        try await load(session, b); try await load(session, a)
        core.disconnect()
        try await wait { core.connectionCount == 2 && session.connectionError == nil }
        let requests = core.resultRequests
        session.select(b.round.key)
        XCTAssertEqual(session.snapshot?.round, b.round)
        XCTAssertFalse(session.hasCurrentSnapshot, "Last-known presentation must not inherit current-stream authority")
        try await wait { core.resultRequests > requests && session.hasCurrentSnapshot }
        XCTAssertGreaterThan(core.resultRequests, requests)
        try await load(session, a)
        let previous = session.aggregateRefreshID
        try core.emit("unknown.provider.event", payload: [:])
        try await wait { session.aggregateRefreshID > previous }
        let beforeUnknownReload = core.resultRequests
        session.select(b.round.key)
        XCTAssertFalse(session.hasCurrentSnapshot, "Unknown event cannot silently authorize an old cached round")
        try await wait { core.resultRequests > beforeUnknownReload && session.hasCurrentSnapshot }
    }
    func testInFlightRESTCannotResurrectRecordAfterEqualRevisionEvent() async throws {
        let a = try snapshot(), b = try snapshot(event: "666", offset: 100)
        let corrected = try snapshot(record: false)
        let (session, core) = try setup(a, [b])
        session.start(); defer { core.releaseHeldResults(); session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        try await load(session, b)
        let prior = session.aggregateRefreshID
        try core.emit("unknown.provider.event", payload: [:])
        try await wait { session.aggregateRefreshID > prior }
        core.holdResults(for: a.round.key)
        session.select(a.round.key)
        try await wait { core.heldCount > 0 }
        core.setSnapshot(corrected)
        let evidence = session.aggregateRefreshID
        try emit(corrected, via: core)
        try await wait { session.aggregateRefreshID > evidence }
        core.releaseHeldResults()
        try await wait { session.snapshot?.results.first?.singleIndicator == nil && session.snapshot != nil }
        XCTAssertEqual(session.snapshot?.results, corrected.results)
    }
    func testVisitedRoundCacheEvictsRatherThanGrowingWithoutBound() async throws {
        let a = try snapshot()
        let events = ["222", "333", "444", "555", "666", "333bf", "333oh", "clock", "minx", "pyram", "skewb", "sq1", "444bf"]
        let others = try events.enumerated().map { try snapshot(event: $0.element, offset: ($0.offset + 1) * 100) }
        let (session, core) = try setup(a, others)
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        for value in others { try await load(session, value) }
        let requests = core.resultRequests
        session.select(a.round.key)
        XCTAssertNil(session.snapshot, "Oldest of more than twelve rounds must be evicted")
        try await wait { session.snapshot?.round == a.round }
        XCTAssertGreaterThan(core.resultRequests, requests)
    }
    func testCompetitorLoadsCoalesceAndSupersededRecordEvidenceIsRejected() async throws {
        let a = try snapshot(), core = FakeCubingChinaTransport(snapshot: a), transport = CompetitorCacheTransport(core)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [a.round])
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        session.start(); defer { session.stop() }
        try await wait { session.snapshot != nil && core.connectionCount == 1 }
        async let first = session.competitorResults(number: 112)
        async let second = session.competitorResults(number: 112)
        let (left, right) = await (first, second)
        XCTAssertEqual(left, right); XCTAssertNotNil(left)
        let calls = await transport.competitorCalls; XCTAssertEqual(calls, 1)
        let pending = Task { await session.competitorResults(number: 112) }
        for _ in 0..<100 {
            if await transport.competitorCalls > 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let corrected = try snapshot(record: false)
        try emit(corrected, via: core)
        let value = await pending.value
        XCTAssertNil(value, "A result-card request must not publish superseded record evidence")
    }
}
