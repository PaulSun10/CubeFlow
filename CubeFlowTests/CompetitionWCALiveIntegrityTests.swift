import XCTest
import Combine
@testable import CubeFlow

private actor WCARecordSocket: CompetitionWCALiveSocket {
    private let ignoresCancellation: Bool
    init(ignoresCancellation: Bool = false) { self.ignoresCancellation = ignoresCancellation }
    private var queue: [URLSessionWebSocketTask.Message] = []
    private var waiter: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private(set) var subscriptions = 0
    private(set) var documents: [String] = []
    private(set) var cancellations = 0
    nonisolated func resume() {}
    nonisolated func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { await closed() }
    }
    private func closed() {
        cancellations += 1
        if !ignoresCancellation { waiter?.resume(throwing: CancellationError()); waiter = nil }
    }
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard case let .string(text) = message,
              let raw = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] else { return }
        let event = raw[3] as? String
        if event == "doc" {
            subscriptions += 1
            documents.append((raw[4] as? [String: Any])?["query"] as? String ?? "")
        }
        let response: [String: Any] = event == "doc" ? ["subscriptionId": "same-id"] : [:]
        try enqueue([raw[0], raw[1], raw[2], "phx_reply", ["status": "ok", "response": response]])
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !queue.isEmpty { return queue.removeFirst() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    private func enqueue(_ value: [Any]) throws {
        let message = URLSessionWebSocketTask.Message.data(try JSONSerialization.data(withJSONObject: value))
        if let waiter { self.waiter = nil; waiter.resume(returning: message) } else { queue.append(message) }
    }
    func update(roundID: String, record: String?) throws {
        let row: [String: Any] = ["id": "result-1", "ranking": 1, "advancing": false,
            "advancingQuestionable": false, "attempts": [["result": 1000]], "best": 1000, "average": 1100,
            "person": ["id": "person-1", "wcaId": "2022FARI05", "name": "Verified Person", "country": ["iso2": "BR", "name": "Brazil"]],
            "singleRecordTag": record as Any? ?? NSNull(), "averageRecordTag": NSNull()]
        try enqueue([NSNull(), NSNull(), "__absinthe__:control", "subscription:data",
            ["subscriptionId": "same-id", "result": ["data": ["roundUpdated": ["id": roundID, "results": [row]]]]]])
    }
}

nonisolated private final class WCASocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [WCARecordSocket]
    init(_ sockets: [WCARecordSocket]) { remaining = sockets }
    func make() -> WCARecordSocket { lock.withLock { remaining.removeFirst() } }
}

private actor WCASnapshotGate {
    private var waiters: [CheckedContinuation<CompetitionWCALiveRound?, Never>] = []
    var count: Int { waiters.count }
    func load() async -> CompetitionWCALiveRound? { await withCheckedContinuation { waiters.append($0) } }
    func release(_ value: CompetitionWCALiveRound?) {
        let pending = waiters; waiters = []; for waiter in pending { waiter.resume(returning: value) }
    }
}

@MainActor final class CompetitionWCALiveIntegrityTests: XCTestCase {
    private let own = "2022FARI05"
    private func round(_ id: String = "round-1", event: String = "333", number: Int = 1,
                       record: String? = "PR", rows: Bool = true, finished: Bool = false) -> CompetitionWCALiveRound {
        let row = CompetitionWCALiveResultPreview(id: "result-1", ranking: 1, personID: "person-1",
            personWCAID: own, name: "Verified Person", region: "Brazil", attempts: [1000], best: 1000,
            average: 1100, isAdvancing: false, isAdvancingQuestionable: false,
            singleRecordTag: record, averageRecordTag: nil)
        return .init(id: id, eventID: event, eventName: event, roundName: "First Round", number: number,
            formatID: "a", numberOfAttempts: 5, sortBy: "average", isFinished: finished,
            advancementType: nil, advancementLevel: nil, isActive: !finished, isOpen: !finished,
            results: rows ? [row] : [])
    }
    private func content(_ rounds: [CompetitionWCALiveRound], id: Int = 11089,
                         records: [CompetitionWCALiveRecord] = []) -> CompetitionWCALiveContent {
        .init(competitionID: id, competitionName: "WCA Live fixture", eventIDs: Array(Set(rounds.map(\.eventID))),
            rounds: rounds, venues: [], records: records,
            competitors: [.init(id: "person-1", wcaID: own)])
    }
    private func personal(_ round: CompetitionWCALiveRound, single: String? = "PR", average: String? = nil) -> CompetitionWCALiveCompetitorContent {
        let result = CompetitionWCALiveCompetitorResult(id: "result-1", ranking: 1,
            isAdvancing: false, isAdvancingQuestionable: false, attempts: [1000], best: 1000, average: 1100,
            singleRecordTag: single, averageRecordTag: average, roundID: round.id, roundName: round.roundName,
            roundNumber: round.number, eventID: round.eventID, eventName: round.eventName, eventRank: nil,
            formatID: "a", numberOfAttempts: 5, sortBy: "average")
        return .init(id: "person-1", name: "Verified Person", wcaID: own, countryISO2: "BR", results: [result])
    }
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<250 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out awaiting native WCA Live lifecycle")
    }
    func testPersonalBeforeOpeningRoundAndRegionalScopeAndAccountIsolation() async {
        let first = round(rows: false), final = round("round-2", number: 2, rows: false)
        let person = personal(first, average: "PR")
        let owner = CompetitionWCALiveSession(personLoader: { _, _ in person })
        owner.configure(content([first, final]), language: "en")
        await owner.loadPersonalRecords(ownWCAID: own)
        XCTAssertEqual(owner.roundTag(first.id, ownWCAID: own), "PR")
        XCTAssertEqual(owner.eventTag("333", ownWCAID: own), "PR")
        var refreshed = content([first, final]); refreshed.clientRequestContext = .now()
        owner.configure(refreshed, language: "en")
        XCTAssertEqual(owner.roundTag(first.id, ownWCAID: own), "PR", "Equivalent metadata must not blank known personal badges while revalidating")
        XCTAssertNil(owner.knownRound(first, competitionID: 11089, language: "en"))
        XCTAssertNil(owner.roundTag(first.id, ownWCAID: nil))
        owner.accept(round(final.id, number: 2, record: "WR"), competitionID: 11089, language: "en")
        XCTAssertEqual(owner.eventTag("333", ownWCAID: own), "WR")
        XCTAssertEqual(owner.roundTag(first.id, ownWCAID: own), "PR")
        XCTAssertEqual(owner.roundTag(final.id, ownWCAID: own), "WR")
        await owner.loadPersonalRecords(ownWCAID: nil)
        XCTAssertNil(owner.roundTag(first.id, ownWCAID: own))
        XCTAssertEqual(owner.roundTag(final.id, ownWCAID: nil), "WR")
    }
    func testKnownSnapshotsSynchronousEmptyRetentionAndIsolationAndEviction() {
        let first = round(record: "WR"), empty = round("round-2", number: 2, rows: false)
        let owner = CompetitionWCALiveSession(roundLimit: 1)
        owner.configure(content([first, empty]), language: "en")
        owner.accept(first, competitionID: 11089, language: "en")
        XCTAssertEqual(owner.knownRound(first, competitionID: 11089, language: "en"), first)
        XCTAssertNil(owner.knownRound(first, competitionID: 11090, language: "en"))
        XCTAssertNil(owner.knownRound(first, competitionID: 11089, language: "zh-Hans"))
        owner.accept(empty, competitionID: 11089, language: "en")
        XCTAssertEqual(owner.knownRound(empty, competitionID: 11089, language: "en")?.results, [])
        XCTAssertNil(owner.knownRound(first, competitionID: 11089, language: "en"))
        XCTAssertEqual(owner.roundTag(first.id, ownWCAID: nil), "WR", "Compact evidence survives full-row eviction")
        owner.accept(round(record: nil, rows: false), competitionID: 11089, language: "en")
        owner.accept(empty, competitionID: 11089, language: "en")
        XCTAssertNil(owner.roundTag(first.id, ownWCAID: nil), "Retractions survive eviction too")
        owner.configure(content([first], id: 11090), language: "en")
        XCTAssertNil(owner.knownRound(first, competitionID: 11090, language: "en"))
        XCTAssertNil(owner.roundTag(first.id, ownWCAID: nil))
    }
    func testIdenticalLiveUpdateBlocksOlderHTTPAndRetainsWCAIdentityAndRetraction() async throws {
        let source = round(record: "WR"), stale = round(record: "NR")
        let gate = WCASnapshotGate(), socket = WCARecordSocket()
        let manager = CompetitionWCALiveRealtimeManager(round: source, languageCode: "en", hasCachedSnapshot: true,
            monitorsNetwork: false, snapshotLoader: { _, _ in await gate.load() }, socketFactory: { _ in socket })
        manager.start(); manager.start()
        defer { manager.stop() }
        try await wait {
            let subscriptions = await socket.subscriptions, requests = await gate.count
            return subscriptions == 1 && requests >= 2
        }
        var publications = 0
        let observation = manager.$round.dropFirst().sink { _ in publications += 1 }
        try await socket.update(roundID: source.id, record: "WR")
        try await wait { manager.hasCurrentSnapshot }
        XCTAssertEqual(publications, 0, "Identical authority must not republish rows")
        await gate.release(stale)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(manager.round.results.first?.singleRecordTag, "WR")
        XCTAssertEqual(manager.round.results.first?.personWCAID, own)
        let documents = await socket.documents
        XCTAssertTrue(documents.first?.contains("wcaId") == true)
        try await socket.update(roundID: source.id, record: nil)
        try await wait { manager.round.results.first?.singleRecordTag == nil }
        XCTAssertEqual(publications, 1)
        withExtendedLifetime(observation) {}
        manager.suspend()
        XCTAssertFalse(manager.hasCurrentSnapshot)
        XCTAssertEqual(manager.roundContentState, .loaded)
    }
    func testSnapshotCancellationABAAndSingleActiveSubscriptionOwner() async throws {
        let source = round(record: "PR", finished: true), gate = WCASnapshotGate()
        let owner = CompetitionWCALiveSession()
        owner.configure(content([source]), language: "en")
        let first = CompetitionWCALiveRealtimeManager(round: source, languageCode: "en", monitorsNetwork: false,
            snapshotLoader: { _, _ in await gate.load() })
        owner.activate(first, competitionID: 11089, language: "en")
        try await wait { await gate.count == 1 }
        owner.deactivate(first)
        owner.activate(first, competitionID: 11089, language: "en")
        try await wait { await gate.count == 2 }
        let second = CompetitionWCALiveRealtimeManager(round: source, languageCode: "en", monitorsNetwork: false,
            snapshotLoader: { round, _ in round })
        owner.activate(second, competitionID: 11089, language: "en")
        owner.deactivate(first)
        try await wait { second.hasCurrentSnapshot }
        await gate.release(round(record: "WR", finished: true))
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(first.round.results.first?.singleRecordTag, "PR", "Stopped owner's late HTTP must be ignored")
        XCTAssertTrue(second.hasCurrentSnapshot, "Stale disappear cannot stop the new owner")
        owner.deactivate(second)
    }
    func testLatePersonalResponseCannotResurrectNewerEmptyRound() async throws {
        let source = round(record: "PR"), person = personal(source)
        var release: CheckedContinuation<CompetitionWCALiveCompetitorContent?, Never>?
        let owner = CompetitionWCALiveSession(personLoader: { _, _ in
            await withCheckedContinuation { release = $0 }
        })
        owner.configure(content([source]), language: "en")
        let task = Task { await owner.loadPersonalRecords(ownWCAID: own) }
        try await wait { release != nil }
        owner.accept(round(record: nil, rows: false), competitionID: 11089, language: "en")
        release?.resume(returning: person)
        await task.value
        XCTAssertNil(owner.roundTag(source.id, ownWCAID: own))
        XCTAssertTrue(owner.personalResults.isEmpty)
    }
    func testRecordLedgerOrdersMetadataPersonalAndFullRoundEvidenceIncludingEmpty() {
        let record = CompetitionWCALiveRecord(id: "r", tag: "WR", type: "single", attemptResult: 1000,
            eventID: "333", eventName: "3x3", roundID: "round-1", personID: "person-1",
            personWCAID: own, personName: "Verified Person", countryName: "Brazil")
        var ledger = CompetitionWCALiveRecordLedger()
        ledger.full([record], roundID: "round-1", observedAt: 1)
        ledger.person([], personID: "person-1", roundID: "round-1", observedAt: 3)
        XCTAssertTrue(ledger.records.isEmpty)
        ledger.full([record], roundID: "round-1", observedAt: 2)
        XCTAssertTrue(ledger.records.isEmpty, "Old metadata cannot retract a newer person correction")
        ledger.full([], roundID: "round-1", observedAt: 4)
        ledger.person([record], personID: "person-1", roundID: "round-1", observedAt: 3)
        XCTAssertTrue(ledger.records.isEmpty)
        ledger.full([record], roundID: "round-1", observedAt: 5)
        XCTAssertEqual(ledger.records, [record])
        ledger.retainRounds([])
        XCTAssertTrue(ledger.records.isEmpty)
    }
    func testOldCodableMetadataRemainsCompatibleAndLanguageInvalidatesCache() throws {
        let source = round()
        let data = try JSONEncoder().encode(content([source]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "competitors"); object.removeValue(forKey: "loadedRoundIDs")
        object.removeValue(forKey: "clientRequestContext")
        let decoded = try JSONDecoder().decode(CompetitionWCALiveContent.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.competitors)
        let owner = CompetitionWCALiveSession()
        owner.configure(decoded, language: "en"); owner.accept(source, competitionID: 11089, language: "en")
        owner.configure(decoded, language: "zh-Hans")
        XCTAssertNil(owner.knownRound(source, competitionID: 11089, language: "zh-Hans"))
        XCTAssertNotNil(owner.content)
    }
    func testReconnectRejectsOldSocketEvenWhenSubscriptionIDIsReused() async throws {
        let first = WCARecordSocket(ignoresCancellation: true), second = WCARecordSocket()
        let factory = WCASocketFactory([first, second]), source = round()
        let manager = CompetitionWCALiveRealtimeManager(round: source, languageCode: "en", monitorsNetwork: false,
            snapshotLoader: { _, _ in nil }, socketFactory: { _ in factory.make() })
        manager.start()
        try await wait { await first.subscriptions == 1 }
        try await first.update(roundID: source.id, record: "PR")
        try await wait { manager.hasCurrentSnapshot }
        manager.stop(); XCTAssertFalse(manager.hasCurrentSnapshot)
        manager.start()
        defer { manager.stop() }
        try await wait { await second.subscriptions == 1 }
        try await second.update(roundID: source.id, record: "NR")
        try await wait { manager.hasCurrentSnapshot && manager.round.results.first?.singleRecordTag == "NR" }
        try await first.update(roundID: source.id, record: "WR")
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(manager.round.results.first?.singleRecordTag, "NR")
        XCTAssertTrue(manager.hasCurrentSnapshot)
    }
    func testNewMetadataCannotResurrectRecordIfItsRequestPredatesLiveRetraction() {
        let source = round(record: "WR")
        var old = content([source]); old.clientRequestContext = .now()
        let owner = CompetitionWCALiveSession()
        owner.configure(old, language: "en")
        owner.accept(source, competitionID: 11089, language: "en")
        owner.accept(round(record: nil, rows: false), competitionID: 11089, language: "en")
        var arriving = content([source], records: [CompetitionWCALiveRecord(id: "old", tag: "WR", type: "single", attemptResult: 1000,
            eventID: source.eventID, eventName: source.eventName, roundID: source.id, personID: "person-1",
            personWCAID: own, personName: "Verified Person", countryName: "Brazil")])
        arriving.clientRequestContext = old.clientRequestContext
        owner.configure(arriving, language: "en")
        XCTAssertNil(owner.roundTag(source.id, ownWCAID: nil))
    }
}
