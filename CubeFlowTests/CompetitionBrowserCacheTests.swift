import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

nonisolated private final class CacheOfflineHTMLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Cached canonical identity must not require an HTML request")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

nonisolated private final class BrowserCacheClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    func now() -> Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { date.addTimeInterval(interval) } }
}

@MainActor final class CompetitionBrowserCacheTests: XCTestCase {
    private var directory: URL!
    private var clock: BrowserCacheClock!
    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("browser-cache-" + UUID().uuidString)
        clock = BrowserCacheClock()
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func query(_ status: CompetitionStatusFilter = .present, year: CompetitionYearFilter = .all) -> CompetitionQuery {
        .init(languageCode: "en", region: .all, events: Set(CompetitionEventFilter.selectableCases), year: year, status: status)
    }
    private func snapshot(count: Int = 1, total: Int? = 1, age: TimeInterval = 0) -> CompetitionCacheSnapshot {
        .init(competitions: Array(repeating: CompetitionPhysicalRegressionFixtures.beijing, count: count),
            totalCount: total, lastUpdated: clock.now().addingTimeInterval(-age))
    }
    private func content(_ name: String) -> CompetitionDetailContent {
        var value = CompetitionDetailContent.empty; value.localizedName = name; return value
    }
    func testOnlyCompleteFreshListsSkipRevalidationAndHistoricalYearsUseMetadataWindow() {
        let now = clock.now()
        XCTAssertTrue(CompetitionCachePolicy.canReuseList(snapshot(age: 30), query: query(), now: now))
        XCTAssertFalse(CompetitionCachePolicy.canReuseList(snapshot(age: 61), query: query(), now: now))
        XCTAssertTrue(CompetitionCachePolicy.canReuseList(snapshot(age: 1800), query: query(.past), now: now))
        XCTAssertFalse(CompetitionCachePolicy.canReuseList(snapshot(total: 2), query: query(), now: now))
        XCTAssertFalse(CompetitionCachePolicy.canReuseList(snapshot(total: nil), query: query(), now: now))
        XCTAssertFalse(CompetitionCachePolicy.canReuseList(snapshot(age: -60), query: query(), now: now))
        XCTAssertTrue(CompetitionCachePolicy.canReuseList(snapshot(count: 0, total: 0), query: query(), now: now))
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        XCTAssertTrue(CompetitionCachePolicy.canReuseList(snapshot(age: 3600), query: query(.past, year: .year(year - 1)), now: now))
        XCTAssertFalse(CompetitionCachePolicy.canReuseList(snapshot(age: 3600), query: query(.past, year: .year(year)), now: now))
    }
    func testQueryDiskRestartBoundsRetentionAndScopeRemainIndependent() async throws {
        let clock = clock!, directory = directory!
        let store = CompetitionQueryCacheStore(directory: directory, now: { clock.now() })
        for index in 0..<20 {
            await store.store(snapshot(), for: "query-\(index)")
            clock.advance(1)
        }
        let restarted = CompetitionQueryCacheStore(directory: directory, now: { clock.now() })
        let oldest = await restarted.snapshot(for: "query-0"), newest = await restarted.snapshot(for: "query-19")
        XCTAssertNil(oldest); XCTAssertEqual(newest?.competitions.count, 1)
        let other = await restarted.snapshot(for: "different-provider-or-filter"); XCTAssertNil(other)
        let file = directory.appendingPathComponent("competition-query-cache-v2.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertLessThanOrEqual(object.count, CompetitionCachePolicy.maximumQueryCount)
        clock.advance(CompetitionCachePolicy.retention + 1)
        let expired = await restarted.snapshot(for: "query-19"); XCTAssertNil(expired)
    }
    func testDetailStaleReadDoesNotRefreshOriginalValidationTime() async throws {
        let clock = clock!, directory = directory!
        let store = CompetitionDetailContentStore(directory: directory, now: { clock.now() })
        await store.store(content("saved info"), for: "section-v2|wca|One|en|info")
        clock.advance(6 * 3600 + 1)
        let restarted = CompetitionDetailContentStore(directory: directory, now: { clock.now() })
        let fresh = await restarted.content(for: "section-v2|wca|One|en|info")
        let stale = await restarted.content(for: "section-v2|wca|One|en|info", allowStale: true)
        XCTAssertNil(fresh); XCTAssertEqual(stale?.localizedName, "saved info")
        let storedMetadata = await restarted.snapshot(for: "section-v2|wca|One|en|info", allowStale: true)
        let metadata = try XCTUnwrap(storedMetadata)
        XCTAssertTrue(metadata.isStale(resource: .info, now: clock.now()))
        XCTAssertEqual(metadata.validatedAt.timeIntervalSince(clock.now()), -(6 * 3600 + 1), accuracy: 0.01)
        let other = await restarted.content(for: "section-v2|cubing|One|en|info", allowStale: true)
        XCTAssertNil(other)
        clock.advance(CompetitionCachePolicy.retention)
        let expired = await restarted.content(for: "section-v2|wca|One|en|info", allowStale: true)
        XCTAssertNil(expired)
    }
    func testDetailCorruptionDoesNotCrashAndProvisionalResourcesNeverHydrateFromDisk() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken JSON".utf8).write(to: directory.appendingPathComponent("competition-detail-cache-v2.json"))
        let store = CompetitionDetailContentStore(directory: directory)
        let missing = await store.content(for: "one", allowStale: true); XCTAssertNil(missing)
        await store.store(content("recovered"), for: "one")
        let recovered = await store.content(for: "one"); XCTAssertEqual(recovered?.localizedName, "recovered")
        for resource in [CompetitionDetailResource.live, .competitors, .tickets] {
            XCTAssertFalse(CompetitionCachePolicy.persists(resource))
            let cached = await CompetitionService.cachedCompetitionResource(resource,
                for: CompetitionPhysicalRegressionFixtures.beijing, languageCode: "en")
            XCTAssertNil(cached)
        }
    }

    func testCachedChinaCanonicalIdentityCanResolveWithoutAnHTMLRequest() async throws {
        let previousSession = CompetitionService.detailSession
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CacheOfflineHTMLProtocol.self]
        let offline = URLSession(configuration: configuration)
        CompetitionService.detailSession = offline
        defer { CompetitionService.detailSession = previousSession; offline.invalidateAndCancel() }
        let id = "CacheIdentity" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let competition = CompetitionSummary(id: id, name: "Cached China", shortDisplayName: nil,
            startDate: .distantPast, endDate: .distantPast, registrationOpen: nil, registrationClose: nil,
            competitorLimit: nil, venue: "", venueAddress: "", venueDetails: nil, city: "Beijing", countryISO2: "CN",
            latitude: nil, longitude: nil, url: "https://cubing.com/competition/\(id)", website: nil,
            dateRange: "", eventIDs: ["333"], championshipTypes: nil, localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil, localizedStatusOverride: nil, localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil)
        XCTAssertNil(CompetitionPublishedIdentity.resolve(competition))
        var info = content("Cached China")
        info.wcaCompetitionID = "VerifiedCanonical2026"
        let key = "section-v2|cubing|\(id)|en|info"
        await CompetitionDetailContentStore.shared.store(info, for: key)
        let resolved = try await CompetitionService.resolvePublishedCompetitionID(for: competition, languageCode: "en")
        XCTAssertEqual(resolved, "VerifiedCanonical2026")
        await CompetitionDetailContentStore.shared.remove(key: key)
        let removed = await CompetitionDetailContentStore.shared.content(for: key, allowStale: true)
        XCTAssertNil(removed)
    }

    func testTopCuberLegacyMigrationIsStaleUntilValidatedAndClearRejectsOldWork() async throws {
        let clock = clock!, directory = directory!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value = CompetitionTopCuberPreview(id: "2020TEST01", name: "Fixture", badges: [])
        let legacy = directory.appendingPathComponent("competition-top-cubers-cache-v1.json")
        try JSONEncoder().encode(["one": [value]]).write(to: legacy)
        let store = CompetitionTopCuberStore(directory: directory, now: { clock.now() })
        let stale = await store.previews(for: "one"), fresh = await store.previews(for: "one", allowStale: false)
        XCTAssertEqual(stale, [value]); XCTAssertNil(fresh)
        await store.store([value], for: "one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "Legacy is retired only after atomic v2 persistence")
        let restarted = CompetitionTopCuberStore(directory: directory, now: { clock.now() })
        let validated = await restarted.previews(for: "one", allowStale: false); XCTAssertEqual(validated, [value])
        clock.advance(6 * 3600 + 1)
        let expiredFresh = await restarted.previews(for: "one", allowStale: false)
        let expiredStale = await restarted.previews(for: "one")
        XCTAssertNil(expiredFresh); XCTAssertEqual(expiredStale, [value])
        let run = await restarted.generation
        await restarted.clear()
        await restarted.store([value], for: "one", expectedGeneration: run)
        let cleared = await restarted.previews(for: "one"); XCTAssertNil(cleared)
    }

    func testTopCuberRefreshPreservesLoadedGeometryAndPublishesOnlyAfterInteraction() async {
        let old = CompetitionTopCuberPreview(id: "old", name: "Old", badges: [])
        let new = CompetitionTopCuberPreview(id: "new", name: "New", badges: [])
        let loader = CompetitionTopCubersLoader(initial: .loaded([old])), interaction = CompetitionListInteraction()
        interaction.setActive(true)
        await loader.load(cache: { [old] }, fetch: { [new] }, identity: "fixture", interaction: interaction, revalidateCached: true)
        XCTAssertEqual(loader.state, .loaded([old]), "No loading/empty footprint or publication during scrolling")
        interaction.setActive(false); loader.publishPending()
        XCTAssertEqual(loader.state, .loaded([new]))
        await loader.load(cache: { [new] }, fetch: { nil }, identity: "fixture", revalidateCached: true)
        XCTAssertEqual(loader.state, .loaded([new]), "Offline refresh must not erase cached rows")
        await loader.load(cache: { [new] }, fetch: { [] }, identity: "fixture", revalidateCached: true)
        XCTAssertEqual(loader.state, .empty, "Authoritative empty is not a failed request")
    }

    func testUnchangedTopCuberCacheDoesNotRepublishRowsOnHostingRecreation() async {
        let value = CompetitionTopCuberPreview(id: "one", name: "One", badges: [])
        let loader = CompetitionTopCubersLoader(initial: .loaded([value]))
        var publications = 0
        let observation = loader.$state.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<8 {
            await loader.load(cache: { [value] }, fetch: { [value] }, identity: "fixture", revalidateCached: true)
        }
        XCTAssertEqual(publications, 0, "Warm reuse must not cause duplicate Browser publications/self-sizing")
        XCTAssertEqual(loader.state, .loaded([value]))
    }
    func testActualBrowserUsesFreshPersistedSnapshotAndAuthoritativeEmptyWithoutPageFetch() async throws {
        let defaults = UserDefaults.standard
        let keys = ["appLanguage", "competition_filter_status", "competition_filter_region", "competition_filter_year",
                    "competition_filter_events", "competition_show_top_cubers"]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            CompetitionBrowserPublicationAcceptance.cache = nil
            CompetitionBrowserPublicationAcceptance.page = nil
            CompetitionBrowserPublicationAcceptance.displayed = nil
            for key in keys { defaults.set(previous[key] ?? nil, forKey: key) }
        }
        defaults.set("en", forKey: "appLanguage"); defaults.set("present", forKey: "competition_filter_status")
        defaults.set("all", forKey: "competition_filter_region"); defaults.set("all", forKey: "competition_filter_year")
        defaults.set(false, forKey: "competition_show_top_cubers")
        defaults.set(CompetitionEventFilter.selectableCases.map(\.rawValue).joined(separator: ","), forKey: "competition_filter_events")
        let date = Date().addingTimeInterval(2 * 86400), id = "CacheWarm" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let row = CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: date, endDate: date,
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "", venueAddress: "",
            venueDetails: nil, city: "Fixture", countryISO2: "US", latitude: nil, longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/\(id)", website: nil, dateRange: "Fixture", eventIDs: ["333"],
            championshipTypes: nil, localizedRegionLineOverride: nil, localizedAddressLineOverride: nil,
            localizedStatusOverride: nil, localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
        var requests = 0
        CompetitionBrowserPublicationAcceptance.page = { _, _ in
            requests += 1; throw CompetitionServiceError.requestFailed
        }
        for rows in [[row], []] {
            CompetitionBrowserPublicationAcceptance.cache = { _ in
                CompetitionCacheSnapshot(competitions: rows, totalCount: rows.count, lastUpdated: Date())
            }
            var displayed: [String]?
            var publication: CompetitionBrowserPublicationSnapshot?
            CompetitionBrowserPublicationAcceptance.displayed = { displayed = $0 }
            let host = UIHostingController(rootView: CompatibleNavigationContainer {
                CompetitionBrowserView(isActive: true)
                    .environment(\.competitionBrowserPublicationEnabled, true)
                    .onPreferenceChange(CompetitionBrowserPublicationKey.self) { publication = $0 }
            })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host; window.makeKeyAndVisible()
            for _ in 0..<200 where (rows.isEmpty ? publication?.ids : displayed) != rows.map(\.id) {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            // An empty Browser uses its existing empty view, not a collection view.
            XCTAssertEqual(rows.isEmpty ? publication?.ids : displayed, rows.map(\.id))
            if rows.isEmpty { XCTAssertEqual(publication?.sourceIDs, []); XCTAssertEqual(publication?.preparedIDs, []) }
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
            window.isHidden = true; window.rootViewController = nil
        }
        XCTAssertEqual(requests, 0, "Fresh complete cache, including empty, must not trigger the page loader")
    }
}
