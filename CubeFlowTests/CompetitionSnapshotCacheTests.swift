import XCTest
@testable import CubeFlow

nonisolated private final class CacheAuditClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func now() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

nonisolated private final class CacheAuditHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var reply: (Data, Int, [String: String], Double) = (Data(), 500, [:], 0)
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static func configure(_ data: Data, status: Int = 200, headers: [String: String] = [:], delay: Double = 0) {
        lock.withLock { reply = (data, status, headers, delay); requests = [] }
    }
    static func captured() -> [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, status, headers, delay) = Self.lock.withLock {
            Self.requests.append(request); return Self.reply
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            if status == -1009 {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: headers.merging(["Content-Type": "application/json"]) { old, _ in old })!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor final class CompetitionSnapshotCacheTests: XCTestCase {
    private var directory: URL!
    private var network: URLSession!
    private var clock: CacheAuditClock!
    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-audit-" + UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CacheAuditHTTP.self]
        network = URLSession(configuration: configuration); clock = CacheAuditClock()
    }
    override func tearDown() {
        network.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func cache(memory: Int = 16 * 1024 * 1024, disk: Int = 96 * 1024 * 1024,
                       count: Int = 64) -> CompetitionSnapshotCache {
        let clock = clock!
        return .init(directory: directory, memoryLimit: memory, diskLimit: disk, countLimit: count, now: { clock.now() })
    }
    private func service(_ cache: CompetitionSnapshotCache) -> PublishedCompetitionService {
        let clock = clock!
        return .init(session: network, cache: cache, now: { clock.now() })
    }
    private func key(_ provider: String = "wca-official", resource: String = "results", schema: Int = 1) -> CompetitionSnapshotKey {
        .init(provider: provider, competition: "Test2025", resource: resource, schema: schema)
    }
    private func body(record: String? = "WR") throws -> Data {
        let rows: [[String: Any]] = ["333", "222"].enumerated().map { index, event in
            ["id": index + 1, "competition_id": "Test2025", "event_id": event, "round_id": 11 + index,
             "round_type_id": "f", "format_id": "a", "pos": 1, "name": "Cache Fixture",
             "wca_id": "2020TEST01", "country_iso2": "CN", "best": 900, "average": 1000,
             "attempts": [900, 1000, 1000, 1000, 1100], "regional_single_record": record ?? NSNull() as Any,
             "regional_average_record": NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }
    private func wait(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for production cache lifecycle")
    }

    func testRestartAndProviderResourceSchemaIsolation() async throws {
        let first = cache(), data = try body()
        await first.store(.init(body: data, validatedAt: clock.now(), etag: "fixture", lastModified: nil), for: key())
        let restarted = cache()
        let loaded = await restarted.entry(for: key())
        XCTAssertEqual(loaded?.body, data)
        XCTAssertEqual(loaded?.etag, "fixture")
        let wrongProvider = await restarted.entry(for: key("cubing"))
        let wrongResource = await restarted.entry(for: key(resource: "scrambles"))
        let wrongSchema = await restarted.entry(for: key(schema: 2))
        XCTAssertNil(wrongProvider); XCTAssertNil(wrongResource); XCTAssertNil(wrongSchema)
    }
    func testCorruptionSchemaMismatchInterruptedWriteAndExpirationRecoverSafely() async throws {
        for corruptVersion in [false, true] {
            let store = cache()
            await store.store(.init(body: try body(), validatedAt: clock.now(), etag: nil, lastModified: nil), for: key())
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            if corruptVersion {
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                json["version"] = 999; try JSONSerialization.data(withJSONObject: json).write(to: file)
            } else { try Data("partial".utf8).write(to: file) }
            let restarted = cache(), missing = await restarted.entry(for: key())
            XCTAssertNil(missing)
        }
        try Data("interrupted write".utf8).write(to: directory.appendingPathComponent(".temporary"))
        let store = cache()
        await store.store(.init(body: try body(), validatedAt: clock.now(), etag: nil, lastModified: nil), for: key())
        clock.advance(CompetitionSnapshotCache.retention + 1)
        let expired = await store.entry(for: key()); XCTAssertNil(expired)
        let temporary = directory.appendingPathComponent(".temporary")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path), "Cache owns only its hashed entries")
    }
    func testMemoryAndDiskEvictionAreBoundedWithoutTruncatingSnapshots() async throws {
        let store = cache(memory: 200, disk: 1500, count: 2)
        let data = Data(repeating: 65, count: 100)
        for resource in ["one", "two", "three"] {
            await store.store(.init(body: data, validatedAt: clock.now(), etag: nil, lastModified: nil), for: key(resource: resource))
            clock.advance(1)
        }
        let restarted = cache(memory: 200, disk: 1500, count: 2)
        let oldest = await restarted.entry(for: key(resource: "one"))
        let newest = await restarted.entry(for: key(resource: "three"))
        XCTAssertNil(oldest); XCTAssertEqual(newest?.body, data)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertLessThanOrEqual(files.count, 2)
        XCTAssertLessThanOrEqual(try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }, 1500)
    }
    func testOfficialWarmRestartUsesDiskWithoutDownloadingAgain() async throws {
        CacheAuditHTTP.configure(try body())
        _ = try await service(cache()).results(competitionID: "Test2025", eventOrder: ["333", "222"])
        let restarted = service(cache())
        let snapshot = try await restarted.resultSnapshot(competitionID: "Test2025", eventOrder: ["222", "333"])
        XCTAssertTrue(snapshot.metrics.cacheHit); XCTAssertEqual(snapshot.data.eventIDs, ["222", "333"])
        XCTAssertEqual(CacheAuditHTTP.captured().count, 1)
    }
    func testValidOversizedResponseStillLoadsWithoutBeingCachedOrTruncated() async throws {
        var data = Data(repeating: 32, count: 16 * 1024 * 1024)
        data.append(try body())
        CacheAuditHTTP.configure(data)
        let cache = cache(), service = service(cache)
        let first = try await service.resultSnapshot(competitionID: "Test2025", eventOrder: [])
        XCTAssertEqual(first.data.results.count, 2)
        let persisted = await cache.entry(for: key()); XCTAssertNil(persisted)
        let second = try await service.resultSnapshot(competitionID: "Test2025", eventOrder: [])
        XCTAssertFalse(second.metrics.cacheHit); XCTAssertEqual(second.data.results.count, 2)
        XCTAssertEqual(CacheAuditHTTP.captured().count, 2)
    }
    func testStaleWhileRevalidatingPublishesBeforeNetworkAndSurvivesFailure() async throws {
        CacheAuditHTTP.configure(try body())
        _ = try await service(cache()).results(competitionID: "Test2025", eventOrder: [])
        clock.advance(3601)
        CacheAuditHTTP.configure(Data(), status: -1009, delay: 0.15)
        let store = PublishedCompetitionStore(service: service(cache()))
        let loading = Task { await store.load(id: "Test2025", events: []) }
        try await wait { store.data != nil && store.loading }
        XCTAssertEqual(store.data?.results.first?.singleBadge, "WR")
        await loading.value
        XCTAssertTrue(store.failed); XCTAssertEqual(store.lifecycle, .published)
        XCTAssertTrue(store.isStale, "Failed revalidation must not relabel saved rows as freshly confirmed")
        XCTAssertEqual(store.data?.results.count, 2)
        let offline = await service(cache()).cachedResults(competitionID: "Test2025", eventOrder: [])
        XCTAssertEqual(offline?.data.results.count, 2)
    }
    func testConditional304RevalidatesWithoutLosingRows() async throws {
        CacheAuditHTTP.configure(try body(), headers: ["ETag": "\"revision-1\"", "Last-Modified": "Mon, 19 Oct 2026 00:00:00 GMT"])
        _ = try await service(cache()).results(competitionID: "Test2025", eventOrder: [])
        clock.advance(3601)
        CacheAuditHTTP.configure(Data(), status: 304)
        let snapshot = try await service(cache()).resultSnapshot(competitionID: "Test2025", eventOrder: [])
        XCTAssertEqual(snapshot.metrics.httpStatus, 304); XCTAssertEqual(snapshot.data.results.count, 2)
        XCTAssertEqual(CacheAuditHTTP.captured().first?.value(forHTTPHeaderField: "If-None-Match"), "\"revision-1\"")
        XCTAssertNotNil(CacheAuditHTTP.captured().first?.value(forHTTPHeaderField: "If-Modified-Since"))
        let cached = try await service(cache()).resultSnapshot(competitionID: "Test2025", eventOrder: [])
        XCTAssertTrue(cached.metrics.cacheHit); XCTAssertEqual(CacheAuditHTTP.captured().count, 1)
    }
    func testRecordRetractionAndAuthoritativeEmptyPersistAndDoNotResurrect() async throws {
        let service = service(cache()), store = PublishedCompetitionStore(service: service)
        CacheAuditHTTP.configure(try body())
        await store.load(id: "Test2025", events: [])
        XCTAssertEqual(store.data?.results.first?.singleBadge, "WR")
        clock.advance(3601); CacheAuditHTTP.configure(try body(record: nil))
        await store.load(id: "Test2025", events: [])
        XCTAssertNil(store.data?.results.first?.singleBadge)
        clock.advance(3601); CacheAuditHTTP.configure(Data("[]".utf8))
        await store.load(id: "Test2025", events: [])
        XCTAssertNil(store.data); XCTAssertEqual(store.lifecycle, .unpublished)
        clock.advance(61); CacheAuditHTTP.configure(try body(record: "NR"))
        await store.load(id: "Test2025", events: [])
        XCTAssertEqual(store.lifecycle, .published); XCTAssertEqual(store.data?.results.first?.singleBadge, "NR")
    }
    func testInvalidSuccessDoesNotErasePreviousValidDiskData() async throws {
        CacheAuditHTTP.configure(try body())
        _ = try await service(cache()).results(competitionID: "Test2025", eventOrder: [])
        clock.advance(3601)
        for data in [Data("not JSON".utf8), try body().replacingCompetitionID()] {
            CacheAuditHTTP.configure(data)
            do { _ = try await service(cache()).results(competitionID: "Test2025", eventOrder: []); XCTFail("Invalid response accepted") }
            catch { }
            let cached = await service(cache()).cachedResults(competitionID: "Test2025", eventOrder: [])
            XCTAssertEqual(cached?.data.results.count, 2)
        }
    }
    func testConcurrentEventOrdersShareOneValidatedNetworkRequest() async throws {
        CacheAuditHTTP.configure(try body(), delay: 0.1)
        let service = service(cache())
        async let a = service.results(competitionID: "Test2025", eventOrder: ["333", "222"])
        async let b = service.results(competitionID: "Test2025", eventOrder: ["222", "333"])
        let (left, right) = try await (a, b)
        XCTAssertEqual(left.eventIDs, ["333", "222"]); XCTAssertEqual(right.eventIDs, ["222", "333"])
        XCTAssertEqual(CacheAuditHTTP.captured().count, 1)
    }
    func testRefreshInvalidatesEveryDerivedEventOrderIncludingRetractionAndEmpty() async throws {
        let service = service(cache())
        CacheAuditHTTP.configure(try body())
        let first = try await service.results(competitionID: "Test2025", eventOrder: ["333", "222"])
        XCTAssertEqual(first.results.first?.singleBadge, "WR")
        CacheAuditHTTP.configure(try body(record: nil))
        _ = try await service.results(competitionID: "Test2025", eventOrder: ["222", "333"], refresh: true)
        let other = try await service.results(competitionID: "Test2025", eventOrder: ["333", "222"])
        XCTAssertNil(other.results.first?.singleBadge)
        XCTAssertEqual(CacheAuditHTTP.captured().count, 1, "A different presentation order must reuse the new canonical body")
        CacheAuditHTTP.configure(Data("[]".utf8))
        _ = try await service.results(competitionID: "Test2025", eventOrder: ["222", "333"], refresh: true)
        let removed = try await service.results(competitionID: "Test2025", eventOrder: ["333", "222"])
        XCTAssertTrue(removed.results.isEmpty, "Deleted results must not survive in another derived model")
        XCTAssertEqual(CacheAuditHTTP.captured().count, 1)
    }
    func testSharedRequestSurvivesOneConsumerCancellationAndClearCancelsRemainingWork() async throws {
        CacheAuditHTTP.configure(try body(), delay: 0.15)
        let store = cache(), service = service(store)
        let a = Task { try await service.results(competitionID: "Test2025", eventOrder: []) }
        let b = Task { try await service.results(competitionID: "Test2025", eventOrder: []) }
        try await wait { !CacheAuditHTTP.captured().isEmpty }
        a.cancel()
        let result = try await b.value
        XCTAssertEqual(result.results.count, 2)
        _ = try? await a.value
        XCTAssertEqual(CacheAuditHTTP.captured().count, 1)
        CacheAuditHTTP.configure(try body(), delay: 0.15)
        let next = Task { try await service.results(competitionID: "Test2025", eventOrder: [], refresh: true) }
        try await wait { !CacheAuditHTTP.captured().isEmpty }
        await service.clear(); _ = try? await next.value
        let removed = await store.entry(for: key()); XCTAssertNil(removed)
    }
    func testScrambleRestartAndOfflineRefreshKeepActualSets() async throws {
        let rows: [[String: Any]] = [["id": 1, "competition_id": "Test2025", "event_id": "333", "round_id": 11,
            "round_type_id": "f", "group_id": "A", "is_extra": false, "scramble_num": 1, "scramble": "R U F"]]
        CacheAuditHTTP.configure(try JSONSerialization.data(withJSONObject: rows))
        _ = try await service(cache()).scrambles(competitionID: "Test2025")
        let store = PublishedCompetitionScramblesStore(service: service(cache()))
        CacheAuditHTTP.configure(Data(), status: 503)
        await store.load(id: "Test2025")
        XCTAssertFalse(store.failed); XCTAssertEqual(store.sets.first?.scrambles.first?.scramble, "R U F")
        XCTAssertEqual(CacheAuditHTTP.captured().count, 0)
        clock.advance(3601)
        await store.load(id: "Test2025")
        XCTAssertTrue(store.failed); XCTAssertEqual(store.sets.first?.groupID, "A")
        XCTAssertTrue(store.isStale)
    }
    func testCachedPublicationHydratesScramblesBeforeSlowResultsRevalidation() async throws {
        let first = service(cache())
        CacheAuditHTTP.configure(try body())
        _ = try await first.results(competitionID: "Test2025", eventOrder: [])
        let rows: [[String: Any]] = [["id": 1, "competition_id": "Test2025", "event_id": "333", "round_id": 11,
            "round_type_id": "f", "group_id": "A", "is_extra": false, "scramble_num": 1, "scramble": "R U F"]]
        CacheAuditHTTP.configure(try JSONSerialization.data(withJSONObject: rows))
        _ = try await first.scrambles(competitionID: "Test2025")
        clock.advance(3601)
        CacheAuditHTTP.configure(Data(), status: 503, delay: 0.2)
        let store = PublishedCompetitionStore(service: service(cache()))
        let work = Task { await store.load(id: "Test2025", events: []) }
        try await wait { store.loading && store.data != nil && !store.scrambles.sets.isEmpty }
        XCTAssertEqual(store.scrambles.sets.first?.scrambles.first?.scramble, "R U F")
        await work.value
        XCTAssertTrue(CacheAuditHTTP.captured().allSatisfy { $0.url!.path.hasSuffix("/results") },
            "Cached hydration must never trigger an early scramble HTTP request")
    }
}

nonisolated private extension Data {
    func replacingCompetitionID() throws -> Data {
        var rows = try JSONSerialization.jsonObject(with: self) as! [[String: Any]]
        rows[0]["competition_id"] = "Another2025"
        return try JSONSerialization.data(withJSONObject: rows)
    }
}
