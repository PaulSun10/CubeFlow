import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

private actor RecordDiscoveryExtras: CubingChinaLiveExtrasTransport {
    private var values: [CubingChinaLiveResult]
    private let podiumValues: [CubingChinaLivePodium]
    private var recordWaiters: [CheckedContinuation<Void, Never>] = []
    private var statisticsWaiters: [CheckedContinuation<Void, Never>] = []
    var holdRecords = false
    var holdStatistics = false
    private(set) var recordCalls = 0

    init(_ values: [CubingChinaLiveResult], podiums: [CubingChinaLivePodium] = []) {
        self.values = values; podiumValues = podiums
    }
    func configure(records: [CubingChinaLiveResult]? = nil, holdRecords: Bool = false, holdStatistics: Bool = false) {
        if let records { values = records }
        self.holdRecords = holdRecords; self.holdStatistics = holdStatistics
    }
    func records(slug: String) async throws -> [CubingChinaLiveResult] {
        recordCalls += 1
        let response = values
        if holdRecords { await withCheckedContinuation { recordWaiters.append($0) } }
        return response
    }
    func podiums(slug: String) async throws -> [CubingChinaLivePodium] { podiumValues }
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank] {
        if holdStatistics { await withCheckedContinuation { statisticsWaiters.append($0) } }
        return []
    }
    func release() {
        holdRecords = false; holdStatistics = false
        recordWaiters.forEach { $0.resume() }; recordWaiters = []
        statisticsWaiters.forEach { $0.resume() }; statisticsWaiters = []
    }
}

@MainActor final class CubingLiveRecordDiscoveryTests: XCTestCase {
    private func fixture() throws -> (CubingChinaLiveBootstrap, [CubingChinaLiveResult]) {
        let rounds = try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
        let records = try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveResult]>.self,
            from: CubingChinaUnifiedFixtures.records).data
        return (try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: rounds), records)
    }
    private func revised(_ round: CubingChinaLiveRound) throws -> CubingChinaLiveRound {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(round)) as? [String: Any])
        json["revision"] = round.revision + 1
        return try JSONDecoder().decode(CubingChinaLiveRound.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func wait(_ predicate: @escaping @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for production state", file: file, line: line)
    }
    private func core(_ bootstrap: CubingChinaLiveBootstrap) -> FakeCubingChinaTransport {
        FakeCubingChinaTransport(snapshot: .init(round: bootstrap.defaultRound, results: []),
            additional: bootstrap.rounds.filter { $0.key != bootstrap.defaultRound.key }.map { .init(round: $0, results: []) })
    }
    private func emit(_ round: CubingChinaLiveRound, via transport: FakeCubingChinaTransport) throws {
        let value = CubingChinaLiveDelta(round: round, upsertedResults: [], removedResultIds: [])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        try transport.emit("result.updated", payload: payload)
    }

    func testInitialSummaryPopulatesUnvisitedRoundsBeforeStatisticsWithoutRoundScan() async throws {
        let (bootstrap, records) = try fixture(), extras = RecordDiscoveryExtras(records)
        await extras.configure(holdStatistics: true)
        defer { Task { await extras.release() } }
        let store = CubingChinaLiveExtrasStore(), transport = core(bootstrap)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        session.start(); defer { session.stop(); store.stop() }
        store.refresh(bootstrap, transport: extras)
        try await wait { !store.records.isEmpty && session.snapshot != nil }
        XCTAssertTrue(store.isLoading, "Record selectors must not wait for unrelated slow statistics")
        let tags = session.roundRecordTags(in: store)
        XCTAssertEqual(tags["666|1"], "WR")
        XCTAssertEqual(tags["777|1"], "CR", "Wu's NR single coexists with a higher CR mean")
        XCTAssertEqual(tags["777|2"], "WR")
        let wu = try XCTUnwrap(store.records.first { $0.eventId == "777" && $0.roundNumber == 1 })
        XCTAssertEqual(wu.singleIndicator, "NR"); XCTAssertEqual(wu.averageIndicator, "CR")
        let events = CubingChinaUnifiedLiveContent<EmptyView>.eventRecordTags(rounds: session.rounds, roundTags: tags)
        XCTAssertEqual(events["666"], "WR"); XCTAssertEqual(events["777"], "WR")
        XCTAssertEqual(session.selectedKey, bootstrap.defaultRound.key)
        XCTAssertEqual(Set(transport.requestedKeys), [bootstrap.defaultRound.key])
        let calls = await extras.recordCalls; XCTAssertEqual(calls, 1)
        await extras.release()
        try await wait { !store.isLoading }
    }

    func testAggregateRevisionInvalidationAndCompleteSnapshotCanClearOldBadge() async throws {
        let (bootstrap, records) = try fixture(), store = CubingChinaLiveExtrasStore()
        let extras = RecordDiscoveryExtras(records), transport = core(bootstrap)
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        store.refresh(bootstrap, transport: extras); session.start()
        defer { store.stop(); session.stop() }
        try await wait { !store.isLoading && session.snapshot != nil && transport.connectionCount > 0 }
        let original = try XCTUnwrap(bootstrap.rounds.first { $0.key.selectionID == "777|2" })
        XCTAssertEqual(session.roundRecordTags(in: store)["777|2"], "WR")
        let updated = try revised(original)
        transport.setSnapshot(.init(round: updated, results: []))
        try emit(updated, via: transport)
        try await wait { session.rounds.contains(updated) }
        XCTAssertNil(session.roundRecordTags(in: store)["777|2"], "Old aggregate revision must not survive SSE metadata")
        XCTAssertEqual(session.roundRecordTags(in: store)["666|1"], "WR")
        // A current full snapshot with no records wins over a same-revision summary.
        let current = try CubingChinaLiveBootstrap.make(slug: bootstrap.slug, rounds: session.rounds)
        store.refresh(current, transport: extras)
        try await wait { !store.isLoading }
        XCTAssertEqual(session.roundRecordTags(in: store)["777|2"], "WR")
        session.select(updated.key)
        try await wait { session.snapshot?.round == updated }
        XCTAssertNil(session.roundRecordTags(in: store)["777|2"])
        XCTAssertEqual(session.selectedKey, updated.key)
    }

    func testCoalescedRefreshUsesLatestMetadataAndRejectsSupersededResponse() async throws {
        let (bootstrap, records) = try fixture(), extras = RecordDiscoveryExtras(records)
        await extras.configure(holdRecords: true)
        defer { Task { await extras.release() } }
        let store = CubingChinaLiveExtrasStore()
        defer { store.stop() }
        store.refresh(bootstrap, transport: extras)
        try await wait { await extras.recordCalls == 1 }
        var publishedCounts: [Int] = []
        let observer = store.$records.dropFirst().sink { publishedCounts.append($0.count) }
        defer { observer.cancel() }
        let rounds = try bootstrap.rounds.map(revised)
        let current = try CubingChinaLiveBootstrap.make(slug: bootstrap.slug, rounds: rounds)
        await extras.configure(records: [])
        store.refresh(current, transport: extras)
        await extras.release()
        try await wait { !store.isLoading }
        let calls = await extras.recordCalls; XCTAssertEqual(calls, 2)
        XCTAssertTrue(publishedCounts.isEmpty, "Superseded rows and an identical empty replacement must not republish")
        XCTAssertTrue(store.roundRecordTags(for: rounds).isEmpty)
    }

    func testCompleteRegionalSummaryWinsOverOldPodiumFlagsButKeepsExplicitPR() async throws {
        let (bootstrap, records) = try fixture()
        let value = try XCTUnwrap(records.first { $0.eventId == "777" && $0.roundNumber == 2 && $0.singleBadge == "WR" })
        let podium = CubingChinaLivePodium(eventId: value.eventId, roundNumber: value.roundNumber,
            results: [value], group: nil, groupIndex: nil)
        let extras = RecordDiscoveryExtras(records, podiums: [podium]), store = CubingChinaLiveExtrasStore()
        defer { store.stop(); Task { await extras.release() } }
        store.refresh(bootstrap, transport: extras)
        try await wait { !store.isLoading }
        XCTAssertEqual(store.roundRecordTags(for: bootstrap.rounds)["777|2"], "WR")
        await extras.configure(records: [], holdStatistics: true)
        store.refresh(bootstrap, transport: extras)
        try await wait { store.records.isEmpty }
        XCTAssertEqual(store.roundRecordTags(for: bootstrap.rounds)["777|2"], "PR")
        XCTAssertTrue(store.isLoading, "Old podium regional flags cannot undo a newly published retraction")
        await extras.release()
        try await wait { !store.isLoading }
    }

    func testLatestCoalescedRoundIdentityAndExplicitPRDoNotChangeRegionalDiscovery() async throws {
        let (bootstrap, records) = try fixture(), extras = RecordDiscoveryExtras(records)
        await extras.configure(holdRecords: true)
        defer { Task { await extras.release() } }
        let store = CubingChinaLiveExtrasStore(); defer { store.stop() }
        store.refresh(bootstrap, transport: extras)
        try await wait { await extras.recordCalls == 1 }
        let current = try CubingChinaLiveBootstrap.make(slug: bootstrap.slug, rounds: bootstrap.rounds.map(revised))
        store.refresh(current, transport: extras)
        await extras.release()
        try await wait { !store.isLoading }
        XCTAssertEqual(store.roundRecordTags(for: current.rounds)["666|1"], "WR")
        XCTAssertTrue(store.roundRecordTags(for: bootstrap.rounds).isEmpty)
        XCTAssertEqual(CubingLiveRecordIndicators.highestDisplay([nil, "PR"]), "PR")
        XCTAssertEqual(CubingLiveRecordIndicators.highestDisplay(["PR", "NR"]), "NR")
        XCTAssertNil(PublishedCompetitionResult.highestBadge(["PR"]), "WCA/global regional semantics are unchanged")
    }

    func testMountedCompetitionRefreshesUnvisitedRecordsOnSameRevisionSSEWithoutRoundFetch() async throws {
        let (bootstrap, records) = try fixture(), extras = RecordDiscoveryExtras(records), transport = core(bootstrap)
        let content = CubingChinaLivePresentation.content(bootstrap, language: "en")
        let host = UIHostingController(rootView: CompatibleNavigationContainer {
            ScrollView {
                CompetitionCubingLiveSection(content: content, appLanguage: "en", liveURL: nil,
                    areCompetitionEventIconsReady: true, modernTransport: transport, extrasTransport: extras,
                    resultCard: CompetitionResultCardState()).padding(16)
            }
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
            window.isHidden = true; window.rootViewController = nil
        }
        try await wait { await extras.recordCalls > 0 && transport.connectionCount > 0 }
        try await Task.sleep(nanoseconds: 200_000_000)
        let calls = await extras.recordCalls
        let unvisited = try XCTUnwrap(bootstrap.rounds.first { $0.key.selectionID == "777|2" })
        await extras.configure(records: records.filter { !$0.belongs(to: unvisited) })
        try emit(unvisited, via: transport)
        try await wait { await extras.recordCalls > calls }
        XCTAssertEqual(Set(transport.requestedKeys), [bootstrap.defaultRound.key], "SSE refresh must only use the competition summary")
        let refreshed = await extras.recordCalls
        transport.disconnect()
        try await wait { await extras.recordCalls > refreshed && transport.connectionCount > 1 }
        XCTAssertEqual(Set(transport.requestedKeys), [bootstrap.defaultRound.key], "Reconnect must not scan unvisited rounds")
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Cubing Live unvisited record refresh"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
