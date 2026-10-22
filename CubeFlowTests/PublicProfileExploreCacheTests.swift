import XCTest
@testable import CubeFlow

nonisolated private final class ProfileExploreClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    func now() -> Date { lock.withLock { date } }
    func advance(_ value: TimeInterval) { lock.withLock { date.addTimeInterval(value) } }
}
private actor ProfileExploreProbe {
    var calls = 0
    var fail = false
    var blocked = false
    var continuations: [CheckedContinuation<Void, Never>] = []
    func count() -> Int { calls }
    func setFailure(_ value: Bool) { fail = value }
    func block() { blocked = true }
    func release() { blocked = false; continuations.forEach { $0.resume() }; continuations = [] }
    func request() async throws {
        calls += 1
        if blocked { await withCheckedContinuation { continuations.append($0) } }
        try Task.checkCancellation()
        if fail { throw URLError(.notConnectedToInternet) }
    }
}

@MainActor final class PublicProfileExploreCacheTests: XCTestCase {
    private var root: URL!
    private var clock: ProfileExploreClock!
    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("public-cache-test-" + UUID().uuidString)
        clock = ProfileExploreClock()
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root); super.tearDown() }
    nonisolated private static func page(_ id: String = "2020TEST01", language: String = "en", count: String = "1") -> WCAPersonResultsPage {
        WCAPersonResultsPage(contentLanguage: language, summary: .init(region: "China", wcaId: id,
            gender: "Male", competitions: count, completedSolves: "5"), previousIdentityText: nil,
            personalRecords: [], medalCollection: nil, recordCollection: nil, resultsSections: [])
    }
    private func profile(_ probe: ProfileExploreProbe) -> WCAPublicProfileCache {
        let clock = clock!
        return WCAPublicProfileCache(directory: root, now: { clock.now() }, pageLoader: { id, language in
            try await probe.request()
            return Self.page(id, language: language)
        }, identityLoader: { _ in throw URLError(.notConnectedToInternet) })
    }
    private func waitCalls(_ probe: ProfileExploreProbe, _ count: Int) async throws {
        for _ in 0..<200 {
            if await probe.count() >= count { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Request did not start")
    }

    func testProfileColdWarmCanonicalIdentityAndLanguageIsolation() async throws {
        let probe = ProfileExploreProbe(), cache = profile(probe)
        let a = try await cache.page(" 2020test01 ", language: "en")
        let b = try await cache.page("2020TEST01", language: "en")
        XCTAssertEqual(a.summary.wcaId, b.summary.wcaId)
        var count = await probe.count(); XCTAssertEqual(count, 1)
        _ = try await cache.page("2020TEST01", language: "zh-Hans")
        _ = try await cache.page("2021TEST02", language: "en")
        count = await probe.count(); XCTAssertEqual(count, 3)
        XCTAssertNil(WCAPublicProfileCache.canonicalID("../../tokens"))
        let mismatch = await cache.cachedPage("2021TEST02", language: "zh-Hans")
        XCTAssertNil(mismatch)
    }
    func testProfileRestartExpiryExplicitRefreshAndOfflineRetention() async throws {
        let probe = ProfileExploreProbe(), first = profile(probe)
        _ = try await first.page("2020TEST01", language: "en")
        let restarted = profile(probe)
        _ = try await restarted.page("2020TEST01", language: "en")
        var count = await probe.count(); XCTAssertEqual(count, 1)
        _ = try await restarted.page("2020TEST01", language: "en", force: true)
        count = await probe.count(); XCTAssertEqual(count, 2)
        clock.advance(901); await probe.setFailure(true)
        do { _ = try await restarted.page("2020TEST01", language: "en"); XCTFail("Expected offline failure") } catch {}
        let saved = await restarted.cachedPage("2020TEST01", language: "en")
        XCTAssertNotNil(saved)
        XCTAssertGreaterThan(clock.now().timeIntervalSince(saved!.lastUpdated), 900)
        clock.advance(31 * 86400)
        let expired = await restarted.cachedPage("2020TEST01", language: "en")
        XCTAssertNil(expired)
    }
    func testProfileCoalescingIndependentCancellationAndClearRejectsLateReply() async throws {
        let probe = ProfileExploreProbe(), cache = profile(probe)
        await probe.block()
        let a = Task { try await cache.page("2020TEST01", language: "en") }
        let b = Task { try await cache.page("2020TEST01", language: "en") }
        try await waitCalls(probe, 1)
        a.cancel(); await Task.yield(); await probe.release()
        do { _ = try await a.value; XCTFail("Cancelled consumer published") } catch {}
        _ = try await b.value
        let count = await probe.count(); XCTAssertEqual(count, 1)
        await probe.block()
        let late = Task { try await cache.page("2020TEST01", language: "en", force: true) }
        try await waitCalls(probe, 2)
        await cache.clear(); await probe.release()
        do { _ = try await late.value; XCTFail("Clear must invalidate late reply") } catch {}
        let absent = await cache.cachedPage("2020TEST01", language: "en"); XCTAssertNil(absent)
    }
    func testProfileWrongIDCannotPoisonCacheAndCorrectionReplacesOldPage() async throws {
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { _, language in Self.page("2021TEST02", language: language) })
        do { _ = try await cache.page("2020TEST01", language: "en"); XCTFail("Wrong identity accepted") } catch {}
        let invalid = await cache.cachedPage("2020TEST01", language: "en"); XCTAssertNil(invalid)
        let good = profile(ProfileExploreProbe())
        _ = try await good.page("2020TEST01", language: "en")
        let corrected = WCAPublicProfileCache(directory: root, pageLoader: { id, language in Self.page(id, language: language, count: "0") })
        _ = try await corrected.page("2020TEST01", language: "en", force: true)
        let stored = await corrected.cachedPage("2020TEST01", language: "en")
        XCTAssertEqual(stored?.page.summary.competitions, "0")
        XCTAssertTrue(stored?.page.resultsSections.isEmpty == true)
    }
    func testProfileViewForceOfflinePreservesSavedBannerAndRevisitRevalidates() async throws {
        let probe = ProfileExploreProbe(), cache = profile(probe)
        _ = try await cache.page("2020TEST01", language: "en")
        let clock = clock!, model = WCAMyResultsViewModel(cache: cache, now: { clock.now() })
        await model.load(wcaId: "2020TEST01", appLanguageCode: "en")
        await probe.setFailure(true)
        await model.load(wcaId: "2020TEST01", appLanguageCode: "en", forceRefresh: true)
        XCTAssertNotNil(model.page); XCTAssertNotNil(model.cachedResultsLastUpdated); XCTAssertNil(model.errorMessage)
        clock.advance(901)
        await model.load(wcaId: "2020TEST01", appLanguageCode: "en")
        let count = await probe.count(); XCTAssertEqual(count, 3)
        XCTAssertFalse(model.isLoading)
    }
    func testProfileViewRejectsSupersededPage() async throws {
        let first = ProfileExploreProbe(); await first.block()
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { id, language in
            if id == "2020TEST01" { try await first.request() }
            return Self.page(id, language: language)
        })
        let model = WCAMyResultsViewModel(cache: cache)
        let a = Task { await model.load(wcaId: "2020TEST01", appLanguageCode: "en") }
        try await waitCalls(first, 1)
        await model.load(wcaId: "2021TEST02", appLanguageCode: "en")
        await first.release(); await a.value
        XCTAssertEqual(model.page?.summary.wcaId, "2021TEST02")
    }
    func testTypedPublicIdentityPersistsWithoutCredentialsAndFailedRolesDoNotRetract() async throws {
        let identity = WCAPersonProfileIdentity(wcaId: "2020TEST01", name: "Public", avatarURL: "https://example.com/a",
            avatarIsDefault: false, countryISO2: "CN", delegateStatus: nil, teams: [],
            roles: [.init(id: 5, groupType: "delegate_regions", groupName: "Public Region", groupFriendlyID: nil, status: "delegate")])
        let cache = WCAPublicProfileCache(directory: root, identityLoader: { _ in .init(identity: identity, complete: true) })
        _ = try await cache.identity("2020TEST01")
        let partial = WCAPublicProfileCache(directory: root, identityLoader: { _ in
            .init(identity: .init(wcaId: "2020TEST01", name: "Public", avatarURL: nil, avatarIsDefault: nil,
                countryISO2: "CN", delegateStatus: nil, teams: [], roles: []), complete: false)
        })
        let kept = try await partial.identity("2020TEST01", force: true)
        XCTAssertEqual(kept.roles.count, 1)
        let complete = WCAPublicProfileCache(directory: root, identityLoader: { _ in
            .init(identity: .init(wcaId: "2020TEST01", name: "Corrected", avatarURL: nil, avatarIsDefault: nil,
                countryISO2: "CN", delegateStatus: nil, teams: [], roles: []), complete: true)
        })
        let retracted = try await complete.identity("2020TEST01", force: true)
        XCTAssertTrue(retracted.roles.isEmpty)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let bytes = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(bytes.contains("access_token")); XCTAssertFalse(bytes.contains("Authorization"))
        }
    }

    func testSnapshotRestartBoundsCorruptionRetentionAndNewestWriteWins() async throws {
        let clock = clock!, root = root!
        func make() -> PublicDataSnapshotStore {
            .init(directory: root, countLimit: 2, diskLimit: 4000, entryLimit: 2000, memoryLimit: 100,
                retention: 100, now: { clock.now() })
        }
        let store = make()
        await store.save(Data("new".utf8), key: "a", fetchedAt: clock.now())
        await store.save(Data("old".utf8), key: "a", fetchedAt: clock.now().addingTimeInterval(-5))
        let first = await make().load("a"); XCTAssertEqual(first?.body, Data("new".utf8))
        clock.advance(1); await store.save(Data("b".utf8), key: "b", fetchedAt: clock.now())
        clock.advance(1); await store.save(Data("c".utf8), key: "c", fetchedAt: clock.now())
        let oldest = await make().load("a"); XCTAssertNil(oldest)
        XCTAssertLessThanOrEqual(PublicDataSnapshotStore.diskBytes(at: root), 4000)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        for file in files { try Data("partial".utf8).write(to: file) }
        let broken = await make().load("b"); XCTAssertNil(broken)
        clock.advance(101)
        let expired = await store.load("c"); XCTAssertNil(expired)
    }
    func testExploreFreshStaleForceAuthoritativeEmptyAndOfflineRetention() async throws {
        let clock = clock!, probe = ProfileExploreProbe()
        let cache = WCAExplorePublicDataCache(directory: root, now: { clock.now() })
        let loader: @Sendable () async throws -> [String] = { try await probe.request(); return ["old"] }
        _ = try await cache.fetch(key: "records", loader: loader)
        let warm = try await cache.fetch(key: "records", loader: loader)
        XCTAssertEqual(warm.value, ["old"])
        var count = await probe.count(); XCTAssertEqual(count, 1)
        clock.advance(901); await probe.setFailure(true)
        do { _ = try await cache.fetch(key: "records", loader: loader); XCTFail("Expected offline") } catch {}
        let saved = await cache.load([String].self, key: "records"); XCTAssertEqual(saved?.value, ["old"])
        await probe.setFailure(false)
        let empty: WCAExplorePublicDataCache.Cached<[String]> = try await cache.fetch(key: "records", force: true) { [] }
        XCTAssertTrue(empty.value.isEmpty)
        let restarted = WCAExplorePublicDataCache(directory: root, now: { clock.now() })
        let persisted = await restarted.load([String].self, key: "records"); XCTAssertTrue(persisted?.value.isEmpty == true)
        count = await probe.count(); XCTAssertEqual(count, 2)
    }
    func testExploreCoalescingCancellationAndClear() async throws {
        let cache = WCAExplorePublicDataCache(directory: root), probe = ProfileExploreProbe()
        await probe.block()
        let loader: @Sendable () async throws -> [Int] = { try await probe.request(); return [1, 2] }
        let a = Task { try await cache.fetch(key: "a", loader: loader) }
        let b = Task { try await cache.fetch(key: "a", loader: loader) }
        try await waitCalls(probe, 1); a.cancel(); await Task.yield(); await probe.release()
        do { _ = try await a.value; XCTFail("Cancelled") } catch {}
        let kept = try await b.value; XCTAssertEqual(kept.value, [1, 2])
        let count = await probe.count(); XCTAssertEqual(count, 1)
        await probe.block()
        let late = Task { try await cache.fetch(key: "a", force: true, loader: loader) }
        try await waitCalls(probe, 2); await cache.clear(); await probe.release()
        do { _ = try await late.value; XCTFail("Late response after clear") } catch {}
        let missing = await cache.load([Int].self, key: "a"); XCTAssertNil(missing)
    }
    func testExploreEndpointKeysSeparateRealScopesButShareCompatibleResponses() throws {
        let a = WCARankingsQuery(eventID: "333", type: .single, region: .all, gender: .all, show: .persons)
        let b = WCARankingsQuery(eventID: "222", type: .single, region: .all, gender: .all, show: .persons)
        XCTAssertNotEqual(WCAExplorePublicDataService.rankingsKey(a), WCAExplorePublicDataService.rankingsKey(b))
        let mixed = WCARecordsQuery(region: .all, gender: .all, show: .mixed)
        let slim = WCARecordsQuery(region: .all, gender: .all, show: .slim)
        XCTAssertEqual(WCAExplorePublicDataService.recordsKey(mixed), WCAExplorePublicDataService.recordsKey(slim))
        XCTAssertNotEqual(ExploreCompetitionCache.key(language: "en", regionCode: "CN"), ExploreCompetitionCache.key(language: "zh-Hans", regionCode: "CN"))
        XCTAssertNotEqual(ExploreCompetitionCache.key(language: "en", regionCode: "CN"), ExploreCompetitionCache.key(language: "en", regionCode: "US"))
        XCTAssertNotEqual(PublicDataSnapshotStore.key(["scope", "a/b", "1"]), PublicDataSnapshotStore.key(["scope", "a?b", "1"]))
        XCTAssertNotEqual(PublicDataSnapshotStore.key(["scope", "a", "1"]), PublicDataSnapshotStore.key(["scope", "a", "2"]))
    }
    func testHomeRestartRetainsWholeSnapshotAndExactKnownLegacyMigration() async throws {
        let value = ExploreCompetitionSnapshot(competitions: [], fetchedAt: clock.now())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("competitions-v2-en-CN.json")
        try JSONEncoder().encode(value).write(to: old)
        let clock = clock!, cache = ExploreCompetitionCache(directory: root, now: { clock.now() })
        let migrated = await cache.load(language: "en", regionCode: "CN")
        XCTAssertEqual(migrated?.fetchedAt, value.fetchedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        let restarted = ExploreCompetitionCache(directory: root, now: { clock.now() })
        let stored = await restarted.load(language: "en", regionCode: "CN"); XCTAssertNotNil(stored)
        let wrong = await restarted.load(language: "zh-Hans", regionCode: "CN"); XCTAssertNil(wrong)
    }
    func testLegacyProfileMigrationValidatesIDAndDoesNotResurrectEvictedEntries() async throws {
        nonisolated struct Legacy: Codable { let page: WCAPersonResultsPage; let lastUpdated: Date }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("legacy.json"), directory = root.appendingPathComponent("v2")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(["2020TEST01|en": Legacy(page: Self.page(), lastUpdated: clock.now()),
            "2021TEST02|en": Legacy(page: Self.page(), lastUpdated: clock.now())]).write(to: legacy)
        let cache = WCAPublicProfileCache(directory: directory, legacyURL: legacy)
        let valid = await cache.cachedPage("2020TEST01", language: "en")
        let invalid = await cache.cachedPage("2021TEST02", language: "en")
        XCTAssertNotNil(valid); XCTAssertNil(invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        await cache.clear()
        let restart = WCAPublicProfileCache(directory: directory, legacyURL: legacy)
        let absent = await restart.cachedPage("2020TEST01", language: "en"); XCTAssertNil(absent)
    }
    func testActualSupportedLegacyExploreKeyDomainHasNoPunctuationCollisions() {
        let regions: [CompetitionRegionFilter] = [.all] + CompetitionContinent.allCases.map { .continent($0) }
            + Locale.isoRegionCodes.map { .country($0) }
        var seen = Set<String>(), total = 0
        for event in CompetitionEventFilter.selectableCases {
            for type in WCAResultType.allCases {
                for region in regions {
                    for gender in WCAPublicGender.allCases {
                        for show in WCARankingsShow.allCases {
                            let key = "rankings-v1-\(event.wcaEventID)-\(type.rawValue)-\(region.id)-\(gender.rawValue)-\(show.rawValue)"
                            let safe = String(key.map { $0.isLetter || $0.isNumber ? $0 : "-" })
                            XCTAssertTrue(seen.insert(safe).inserted, key)
                            total += 1
                        }
                    }
                }
            }
        }
        for region in regions {
            for gender in WCAPublicGender.allCases {
                for show in WCARecordsShow.allCases {
                    let key = "records-v1-\(region.id)-\(gender.rawValue)-\(show.rawValue)"
                    let safe = String(key.map { $0.isLetter || $0.isNumber ? $0 : "-" })
                    XCTAssertTrue(seen.insert(safe).inserted, key)
                    total += 1
                }
            }
        }
        XCTAssertEqual(seen.count, total)
        // Arbitrary inputs do collide in the old representation; full-key v2 does not.
        XCTAssertEqual("a/b".map { $0.isLetter ? $0 : "-" }, "a?b".map { $0.isLetter ? $0 : "-" })
    }
    func testExploreOldLossyFileIsSafelyInvalidatedAndNewestValidPayloadWins() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("a-b.json")
        try JSONEncoder().encode(WCAExplorePublicDataCache.Cached(value: ["ambiguous"], fetchedAt: clock.now())).write(to: old)
        let cache = WCAExplorePublicDataCache(directory: root)
        let a = await cache.load([String].self, key: "a/b"), b = await cache.load([String].self, key: "a?b")
        XCTAssertNil(a); XCTAssertNil(b)
        await cache.save(["correct"], key: "a/b")
        let restart = WCAExplorePublicDataCache(directory: root)
        let saved = await restart.load([String].self, key: "a/b"); XCTAssertEqual(saved?.value, ["correct"])
        let wrong = await restart.load([String].self, key: "a?b"); XCTAssertNil(wrong)
    }

    func testHomeRefreshCoalescesAndClearRejectsInFlightSnapshot() async throws {
        let cache = ExploreCompetitionCache(directory: root), probe = ProfileExploreProbe()
        await probe.block()
        let load: @Sendable () async throws -> [CompetitionSummary] = { try await probe.request(); return [] }
        let a = Task { try await cache.refresh(language: "en", regionCode: "CN", loader: load) }
        let b = Task { try await cache.refresh(language: "en", regionCode: "CN", loader: load) }
        try await waitCalls(probe, 1); await probe.release()
        _ = try await a.value; _ = try await b.value
        let count = await probe.count(); XCTAssertEqual(count, 1)
        await probe.block()
        let late = Task { try await cache.refresh(language: "en", regionCode: "CN", loader: load) }
        try await waitCalls(probe, 2); await cache.clear(); await probe.release()
        do { _ = try await late.value; XCTFail("Cleared Home snapshot must not return") } catch {}
        let missing = await cache.load(language: "en", regionCode: "CN"); XCTAssertNil(missing)
    }
    func testRecentAggregateCoalescesPartialIsNotPersistedAndClearRejectsLateCommit() async throws {
        let cache = WCAExplorePublicDataCache(directory: root), probe = ProfileExploreProbe()
        await probe.block()
        let load: @Sendable () async throws -> ExploreRecentRecordsSnapshot = {
            try await probe.request()
            return .init(records: [], fetchedAt: Date(), hasPartialFailure: false)
        }
        let a = Task { try await cache.recentRecords(key: "recent", loader: load) }
        let b = Task { try await cache.recentRecords(key: "recent", loader: load) }
        try await waitCalls(probe, 1); await probe.release()
        _ = try await a.value; _ = try await b.value
        let count = await probe.count(); XCTAssertEqual(count, 1)
        let full = await cache.load([WCARecentRecord].self, key: "recent")
        XCTAssertNotNil(full)
        _ = try await cache.recentRecords(key: "recent") { .init(records: [], fetchedAt: Date().addingTimeInterval(1), hasPartialFailure: true) }
        let preserved = await cache.load([WCARecentRecord].self, key: "recent")
        XCTAssertEqual(full?.fetchedAt, preserved?.fetchedAt)
        await probe.block()
        let late = Task { try await cache.recentRecords(key: "recent", loader: load) }
        try await waitCalls(probe, 2); await cache.clear(); await probe.release()
        do { _ = try await late.value; XCTFail("Cleared aggregate must not return") } catch {}
        let missing = await cache.load([WCARecentRecord].self, key: "recent"); XCTAssertNil(missing)
    }
    func testRecordsViewRejectsSupersededResponseAndKeepsSavedStateOnFailure() async throws {
        let cache = WCAExplorePublicDataCache(directory: root), probe = ProfileExploreProbe()
        await probe.block()
        let old = WCARecordsQuery(region: .all, gender: .all, show: .history)
        let current = WCARecordsQuery(region: .country("CN"), gender: .all, show: .history)
        let date = Date().addingTimeInterval(-1000)
        await cache.save(WCARecordsResponse(records: ["333": []], timestamp: "old"), key: WCAExplorePublicDataService.recordsKey(current), now: date)
        let model = ExploreRecordsViewModel(cache: cache) { query, _ in
            if query.region == .all { try await probe.request(); return .init(records: ["222": []], timestamp: "stale") }
            throw URLError(.notConnectedToInternet)
        }
        let a = Task { await model.load(old) }
        try await waitCalls(probe, 1)
        await model.load(current)
        await probe.release(); await a.value
        XCTAssertNotNil(model.records["333"]); XCTAssertNil(model.records["222"])
        XCTAssertEqual(model.fetchedAt, date); XCTAssertTrue(model.failed)
        XCTAssertFalse(model.isLoading)
    }
    func testRankingsViewHonorsFreshDiskTimestampAndForceRefresh() async throws {
        let cache = WCAExplorePublicDataCache(directory: root), probe = ProfileExploreProbe()
        let query = WCARankingsQuery(eventID: "333", type: .single, region: .all, gender: .all, show: .persons)
        let date = Date().addingTimeInterval(-100)
        await cache.save(WCARankingsResponse(rankings: [], timestamp: "verified"), key: WCAExplorePublicDataService.rankingsKey(query), now: date)
        let model = ExploreRankingsViewModel(cache: cache) { _, _ in
            try await probe.request(); throw URLError(.notConnectedToInternet)
        }
        await model.load(query)
        var count = await probe.count(); XCTAssertEqual(count, 0)
        XCTAssertEqual(model.fetchedAt, date)
        await model.load(query, force: true)
        count = await probe.count(); XCTAssertEqual(count, 1)
        XCTAssertTrue(model.failed); XCTAssertEqual(model.fetchedAt, date)
    }
    func testProfileOptionalSupplementaryCacheIsBoundedAndCoalesced() async throws {
        let store = WCAResultsSupplementalStore(), probe = ProfileExploreProbe()
        await probe.block()
        let a = Task { await store.localizedCompetitionNames { try? await probe.request(); return ["a": "Name"] } }
        let b = Task { await store.localizedCompetitionNames { try? await probe.request(); return ["a": "Name"] } }
        try await waitCalls(probe, 1); await probe.release()
        _ = await a.value; _ = await b.value
        let count = await probe.count(); XCTAssertEqual(count, 1)
        await store.clear()
        let bounded = await store.localizedCompetitionNames {
            Dictionary(uniqueKeysWithValues: (0..<6000).map { ("competition-\($0)", "Name") })
        }
        XCTAssertEqual(bounded.count, 4096)
    }

    func testActualProfileHTTPParserIdentityRolesAndPublicOnlyPersistence() async throws {
        PublicProfileFixtureHTTP.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PublicProfileFixtureHTTP.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let cache = WCAPublicProfileCache(directory: root, session: session)
        let page = try await cache.page("2020test01", language: "zh-Hans")
        XCTAssertEqual(page.summary.wcaId, "2020TEST01")
        XCTAssertTrue(page.resultsSections.isEmpty)
        let identity = try await cache.identity("2020TEST01")
        XCTAssertEqual(identity.name, "Public Fixture"); XCTAssertTrue(identity.roles.isEmpty)
        _ = try await cache.identity("2020TEST01")
        _ = try await cache.page("2020TEST01", language: "zh-Hans")
        let requests = PublicProfileFixtureHTTP.captured()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Accept-Language")?.contains("zh") == true)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        let restarted = WCAPublicProfileCache(directory: root, session: session)
        let saved = try await restarted.identity("2020TEST01")
        XCTAssertEqual(saved.name, "Public Fixture")
        XCTAssertEqual(PublicProfileFixtureHTTP.captured().count, 3)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for file in files {
            let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let payload = Data(base64Encoded: envelope["body"] as! String)!
            let text = String(decoding: payload, as: UTF8.self)
            XCTAssertFalse(text.contains("not-to-be-persisted")); XCTAssertFalse(text.contains("email"))
        }
    }

    func testPublicProfileIdentityViewRejectsOldPersonResponse() async throws {
        let probe = ProfileExploreProbe(); await probe.block()
        let cache = WCAPublicProfileCache(directory: root, identityLoader: { id in
            if id == "2020TEST01" { try await probe.request() }
            return .init(identity: .init(wcaId: id, name: id, avatarURL: nil, avatarIsDefault: nil,
                countryISO2: "CN", delegateStatus: nil, teams: [], roles: []), complete: true)
        })
        let model = WCAMyResultsViewModel(cache: cache)
        let old = Task { await model.loadIdentity(wcaId: "2020TEST01") }
        try await waitCalls(probe, 1)
        await model.loadIdentity(wcaId: "2021TEST02")
        await probe.release(); await old.value
        XCTAssertEqual(model.personIdentity?.wcaId, "2021TEST02")
    }
    func testOwnerDiskBudgetsEvictAcrossManyQueryAndHomeScopes() async throws {
        let clock = clock!, apiRoot = root.appendingPathComponent("api"), homeRoot = root.appendingPathComponent("home")
        let api = WCAExplorePublicDataCache(directory: apiRoot, now: { clock.now() })
        let home = ExploreCompetitionCache(directory: homeRoot, now: { clock.now() })
        for index in 0..<110 {
            clock.advance(1)
            await api.save([index], key: "query-\(index)", now: clock.now())
            await home.save(.init(competitions: [], fetchedAt: clock.now()), language: "en", regionCode: "scope-\(index)")
        }
        let apiFiles = try FileManager.default.contentsOfDirectory(at: apiRoot, includingPropertiesForKeys: nil)
        let homeFiles = try FileManager.default.contentsOfDirectory(at: homeRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(apiFiles.count, 96); XCTAssertEqual(homeFiles.count, 24)
        let restarted = WCAExplorePublicDataCache(directory: apiRoot, now: { clock.now() })
        let old = await restarted.load([Int].self, key: "query-0"), current = await restarted.load([Int].self, key: "query-109")
        XCTAssertNil(old); XCTAssertEqual(current?.value, [109])
    }
    func testProfileExpirationStillDisplaysLastKnownIdentityWithoutRefreshingItsDate() async throws {
        let clock = clock!, probe = ProfileExploreProbe()
        let identity = WCAPersonProfileIdentity(wcaId: "2020TEST01", name: "Saved", avatarURL: nil,
            avatarIsDefault: nil, countryISO2: "CN", delegateStatus: nil, teams: [], roles: [])
        let cache = WCAPublicProfileCache(directory: root, now: { clock.now() }, identityLoader: { _ in
            try await probe.request(); return .init(identity: identity, complete: true)
        })
        _ = try await cache.identity("2020TEST01")
        clock.advance(3601); await probe.setFailure(true)
        let offline = try await cache.identity("2020TEST01")
        XCTAssertEqual(offline.name, "Saved")
        _ = try await cache.identity("2020TEST01")
        let calls = await probe.count(); XCTAssertEqual(calls, 3)
        clock.advance(31 * 86400)
        do { _ = try await cache.identity("2020TEST01"); XCTFail("Expired beyond retention") } catch {}
    }

    func testProfileOwnerEvictionAndCorruptTypedPageRecoverThroughNetwork() async throws {
        let clock = clock!, probe = ProfileExploreProbe(), directory = root!
        let cache = WCAPublicProfileCache(directory: directory, now: { clock.now() }, pageLoader: { id, language in
            try await probe.request(); return Self.page(id, language: language)
        })
        var ids: [String] = []
        for index in 0..<66 {
            let letter = String(UnicodeScalar(65 + index % 26)!)
            let id = "2020TES\(letter)" + String(format: "%02d", index / 26)
            ids.append(id); clock.advance(1)
            _ = try await cache.page(id, language: "en")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 64)
        let restarted = WCAPublicProfileCache(directory: directory, now: { clock.now() }, pageLoader: { id, language in
            try await probe.request(); return Self.page(id, language: language)
        })
        let evicted = await restarted.cachedPage(ids[0], language: "en"); XCTAssertNil(evicted)
        for file in files { try Data("broken-cache".utf8).write(to: file) }
        let corrupt = await restarted.cachedPage(ids.last!, language: "en"); XCTAssertNil(corrupt)
        let recovered = try await restarted.page(ids.last!, language: "en")
        XCTAssertEqual(recovered.summary.wcaId, ids.last!)
        let calls = await probe.count(); XCTAssertEqual(calls, 67)
    }

    func testColdPartialIdentitySurvivesRestartButNeverCountsAsVerifiedEmptyRoles() async throws {
        let clock = clock!, probe = ProfileExploreProbe()
        let value = WCAPersonProfileIdentity(wcaId: "2020TEST01", name: "Public Base", avatarURL: "https://example.com/a",
            avatarIsDefault: nil, countryISO2: "CN", delegateStatus: nil, teams: [], roles: [])
        let first = WCAPublicProfileCache(directory: root, now: { clock.now() }, identityLoader: { _ in
            try await probe.request(); return .init(identity: value, complete: false)
        })
        _ = try await first.identity("2020TEST01")
        let restarted = WCAPublicProfileCache(directory: root, now: { clock.now() }, identityLoader: { _ in
            try await probe.request(); throw URLError(.notConnectedToInternet)
        })
        let offline = try await restarted.identity("2020TEST01")
        XCTAssertEqual(offline.name, "Public Base")
        XCTAssertEqual(offline.avatarURL, value.avatarURL)
        _ = try await restarted.identity("2020TEST01")
        let calls = await probe.count(); XCTAssertEqual(calls, 3, "Incomplete roles must retry, never use the complete-identity TTL")
    }

}

nonisolated private final class PublicProfileFixtureHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var rolesStatus = 200
    static func reset() { lock.withLock { requests = []; rolesStatus = 200 } }
    static func captured() -> [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let roleStatus = Self.lock.withLock { Self.requests.append(request); return Self.rolesStatus }
        let path = request.url!.path
        let body: String
        if path.contains("user_roles") { body = "[]" }
        else if path.contains("api/v0/users") {
            body = #"{"user":{"id":101,"name":"Public Fixture","avatar":{"url":"https://example.com/public.png"},"country_iso2":"CN","teams":[],"email":"not-to-be-persisted@example.com"}}"#
        } else {
            body = """
            <div class="details"><table><tbody><tr><td>China</td><td>2020TEST01</td><td>Male</td><td>0</td><td>0</td></tr></tbody></table></div>
            <div class="personal-records"><table><tbody></tbody></table></div>
            <table><tbody class="event-333"></tbody></table>
            """
        }
        let status = path.contains("user_roles") ? roleStatus : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
