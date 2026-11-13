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

@MainActor private final class BrowserLocalizationGate {
    private(set) var requests = 0
    private(set) var finished = false
    private var continuation: CheckedContinuation<[String: LocalizedCompetitionInfo], Never>?

    func load() async -> [String: LocalizedCompetitionInfo] {
        requests += 1
        let result: [String: LocalizedCompetitionInfo] = await withCheckedContinuation { continuation = $0 }
        finished = true
        return result
    }

    func release(_ names: [String: LocalizedCompetitionInfo] = [:]) {
        continuation?.resume(returning: names)
        continuation = nil
    }
}

/// A data-source acknowledgement is not a native layout acknowledgement.
/// Establish real, stable self-sizing/inset geometry before the test scrolls.
@MainActor private final class BrowserNativeLayoutSettlement: NSObject {
    private struct Sample: Equatable {
        let offset: CGPoint
        let size: CGSize
        let bounds: CGRect
        let top: CGFloat
        let bottom: CGFloat
    }
    private weak var collection: UICollectionView?
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Error>?
    private var last: Sample?
    private var stable = 0
    private var frames = 0

    static func wait(for collection: UICollectionView) async throws {
        let observer = BrowserNativeLayoutSettlement()
        observer.collection = collection
        try await withCheckedThrowingContinuation { continuation in
            observer.continuation = continuation
            let link = CADisplayLink(target: observer, selector: #selector(observer.frame))
            observer.link = link
            link.add(to: .main, forMode: .common)
        }
    }

    @objc private func frame() {
        frames += 1
        guard let collection else { finish(CancellationError()); return }
        collection.window?.layoutIfNeeded()
        collection.layoutIfNeeded()
        let sample = Sample(offset: collection.contentOffset, size: collection.contentSize, bounds: collection.bounds,
                            top: collection.adjustedContentInset.top, bottom: collection.adjustedContentInset.bottom)
        stable = sample == last ? stable + 1 : 0
        last = sample
        if stable >= 3, sample.size.height > sample.bounds.height,
           !collection.isDragging, !collection.isDecelerating { finish(nil) }
        else if frames >= 120 { finish(URLError(.timedOut)) }
    }

    private func finish(_ error: Error?) {
        link?.invalidate(); link = nil
        let pending = continuation; continuation = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}

@MainActor final class CompetitionBrowserCacheTests: XCTestCase {
    private static var localizationFixtureDay = 0
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

    func testCacheOnlyLocalizationDoesNotStartOrJoinOptionalFetch() async throws {
        let previous = CompetitionService.localizedCompetitionNamesForTesting
        let gate = BrowserLocalizationGate()
        CompetitionService.localizedCompetitionNamesForTesting = (
            CompetitionLocalizedNameStore(directory: directory), { _ in await gate.load() })
        defer { gate.release(); CompetitionService.localizedCompetitionNamesForTesting = previous }
        let row = localizationRow(id: "cacheonly", name: "Canonical", date: Date().addingTimeInterval(86400))
        let first = await CompetitionService.localizeCompetitionNamesIfNeeded([row], languageCode: "zh-Hans", cachedOnly: true)
        XCTAssertEqual(first, [row]); XCTAssertEqual(gate.requests, 0)

        let enrichment = Task { await CompetitionService.localizeCompetitionNamesIfNeeded([row], languageCode: "zh-Hans") }
        defer { enrichment.cancel() }
        try await waitForLocalization("cache_only.optional_fetch_started") { gate.requests == 1 }
        var whilePending: [CompetitionSummary]?
        let cachedRead = Task {
            whilePending = await CompetitionService.localizeCompetitionNamesIfNeeded([row], languageCode: "zh-Hans", cachedOnly: true)
        }
        defer { cachedRead.cancel() }
        try await waitForLocalization("cache_only.read_returns_while_fetch_pending") { whilePending != nil }
        XCTAssertEqual(whilePending, [row]); XCTAssertFalse(gate.finished)

        gate.release(localizationNames([row]))
        let enriched = await enrichment.value
        let warm = await CompetitionService.localizeCompetitionNamesIfNeeded([row], languageCode: "zh-Hans", cachedOnly: true)
        XCTAssertEqual(warm, enriched)
        XCTAssertEqual(warm.first?.name, "Localized Canonical")
        XCTAssertEqual(gate.requests, 1)
        let restarted = CompetitionLocalizedNameStore(directory: directory)
        CompetitionService.localizedCompetitionNamesForTesting = (restarted, { _ in XCTFail("Disk hit must not fetch"); return [:] })
        let restored = await CompetitionService.localizeCompetitionNamesIfNeeded([row], languageCode: "zh-Hans", cachedOnly: true)
        XCTAssertEqual(restored, enriched)
    }

    func testActualBrowserPublishesCachedRowsBeforeOptionalLocalizationCompletes() async throws {
        try await exerciseCachedLocalization(.localized)
    }

    func testActualBrowserKeepsCachedRowsWhenOptionalLocalizationFails() async throws {
        try await exerciseCachedLocalization(.unavailable)
    }

    func testActualBrowserRejectsLateCachedLocalizationAfterSameQueryRefresh() async throws {
        try await exerciseCachedLocalization(.refresh)
    }

    func testActualBrowserRejectsLateCachedLocalizationAcrossFilterABA() async throws {
        try await exerciseCachedLocalization(.filterABA)
    }

    func testActualBrowserRevalidatesStaleCanonicalCacheWhileLocalizationIsPending() async throws {
        try await exerciseCachedLocalization(.stale)
    }

    private enum LocalizationCompletion { case localized, unavailable, refresh, filterABA, stale }

    private func exerciseCachedLocalization(_ completion: LocalizationCompletion) async throws {
        let defaults = UserDefaults.standard
        let keys = ["appLanguage", "competition_filter_status", "competition_filter_region", "competition_filter_year",
                    "competition_filter_events", "competition_show_top_cubers", "competitionCardStyle"]
        let previousDefaults = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let previousLocalization = CompetitionService.localizedCompetitionNamesForTesting
        let previousObserver = CompetitionBrowserView.cachedLocalizationRowsForTesting
        let previousCompletion = CompetitionBrowserView.cachedLocalizationDidFinishForTesting
        let previousScope = CompetitionBrowserPublicationAcceptance.scope
        let previousCache = CompetitionBrowserPublicationAcceptance.cache
        let previousPage = CompetitionBrowserPublicationAcceptance.page
        let previousDisplayed = CompetitionBrowserPublicationAcceptance.displayed
        let previousNow = CompetitionBrowserPublicationAcceptance.now
        let gate = BrowserLocalizationGate()
        let scope = UUID()
        CompetitionBrowserPublicationAcceptance.scope = scope
        CompetitionService.localizedCompetitionNamesForTesting = (
            CompetitionLocalizedNameStore(directory: directory), { _ in await gate.load() })
        // Keep runtime-cache identities isolated without clearing another test's snapshots.
        Self.localizationFixtureDay += 1
        let now = Date(timeIntervalSince1970: 2_000_000_000 + Double(Self.localizationFixtureDay) * 86400)
        CompetitionBrowserPublicationAcceptance.now = { now }
        let prefix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let rows = (0..<24).map { localizationRow(id: prefix + String($0), name: "Canonical \($0)", date: now.addingTimeInterval(86400)) }
        let replacement = localizationRow(id: prefix + "replacement", name: "Fresh replacement", date: now.addingTimeInterval(86400))
        let recent = localizationRow(id: prefix + "recent", name: "Recent", date: now.addingTimeInterval(-86400))
        var presentReads = 0
        var pageRequests = 0
        var pendingPage: CheckedContinuation<CompetitionPageResult, Never>?
        let cachedAt = Date().addingTimeInterval(completion == .stale ? -120 : 0)
        CompetitionBrowserPublicationAcceptance.cache = { query in
            let cached: [CompetitionSummary]
            if query.status == .recent { cached = [recent] }
            else {
                presentReads += 1
                cached = completion == .filterABA && presentReads > 1 ? [replacement] : rows
            }
            return CompetitionCacheSnapshot(competitions: cached, totalCount: cached.count, lastUpdated: cachedAt)
        }
        CompetitionBrowserPublicationAcceptance.page = { _, _ in
            pageRequests += 1
            if completion == .stale {
                return await withCheckedContinuation { pendingPage = $0 }
            }
            return CompetitionPageResult(competitions: [replacement], receivedCount: 1, nextPage: nil, totalCount: 1)
        }
        var publications: [[String: String]] = []
        var displayed: [String] = []
        var displayCount = 0
        var completedRequests: [[String]] = []
        CompetitionBrowserView.cachedLocalizationRowsForTesting = { publications.append($0) }
        CompetitionBrowserView.cachedLocalizationDidFinishForTesting = { completedRequests.append($0) }
        CompetitionBrowserPublicationAcceptance.displayed = { displayed = $0; displayCount += 1 }
        defer {
            gate.release()
            pendingPage?.resume(returning: CompetitionPageResult(competitions: [], receivedCount: 0, nextPage: nil, totalCount: 0))
            CompetitionService.localizedCompetitionNamesForTesting = previousLocalization
            CompetitionBrowserView.cachedLocalizationRowsForTesting = previousObserver
            CompetitionBrowserView.cachedLocalizationDidFinishForTesting = previousCompletion
            CompetitionBrowserPublicationAcceptance.scope = previousScope
            CompetitionBrowserPublicationAcceptance.cache = previousCache
            CompetitionBrowserPublicationAcceptance.page = previousPage
            CompetitionBrowserPublicationAcceptance.displayed = previousDisplayed
            CompetitionBrowserPublicationAcceptance.now = previousNow
            for key in keys {
                if let value = previousDefaults[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("zh-Hans", forKey: "appLanguage")
        defaults.set("present", forKey: "competition_filter_status")
        defaults.set("all", forKey: "competition_filter_region")
        defaults.set("all", forKey: "competition_filter_year")
        defaults.set(CompetitionEventFilter.threeByThree.rawValue, forKey: "competition_filter_events")
        defaults.set(false, forKey: "competition_show_top_cubers")
        defaults.set(CompetitionCardStyleOption.list.rawValue, forKey: "competitionCardStyle")
        let host = UIHostingController(rootView: CompatibleNavigationContainer {
            CompetitionBrowserView(isActive: true)
                .environment(\.competitionBrowserPublicationEnabled, true)
                .environment(\.competitionBrowserPublicationScope, scope)
        })
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.windowLevel = .alert + 1
        host.loadViewIfNeeded()
        host.view.frame = window.bounds
        window.rootViewController = host; window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        defer {
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
            window.isHidden = true; window.rootViewController = nil
        }
        let canonicalNames = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.name) })
        try await waitForLocalization("browser.canonical_rows_mounted_while_localization_pending") {
            gate.requests == 1 && displayed == rows.map(\.id) && publications.last == canonicalNames
        }
        XCTAssertFalse(gate.finished, "Canonical cached rows must mount while optional localization is still suspended")
        if completion == .stale {
            try await waitForLocalization("browser.stale_cache_revalidation_started") { pageRequests == 1 && pendingPage != nil }
            XCTAssertEqual(cachedAt.timeIntervalSinceNow, -120, accuracy: 5)
        } else {
            XCTAssertEqual(pageRequests, 0, "Fresh complete cache must not download competition pages")
        }
        var mountedCollection: UICollectionView?
        try await waitForLocalization("browser.collection_attached_with_nonzero_bounds") {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            mountedCollection = localizationDescendants(window).compactMap { $0 as? UICollectionView }.first {
                $0.window === window && !$0.bounds.isEmpty
            }
            return mountedCollection != nil
        }
        let collection = try XCTUnwrap(mountedCollection)
        try await BrowserNativeLayoutSettlement.wait(for: collection)
        let dataSource = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<Int, String>)
        let originalNativeIDs = dataSource.snapshot().itemIdentifiers
        let originalCompetitionIDs = originalNativeIDs.filter { $0.hasPrefix("competition:") }
        XCTAssertEqual(originalCompetitionIDs.count, rows.count)
        XCTAssertTrue(zip(originalCompetitionIDs, rows).allSatisfy { identifier, row in
            identifier.hasPrefix("competition:\(row.id):")
        }, "The preserved native identity includes the existing content hash")
        // Establish a real interior row via the layout's coordinates, not a
        // fixed point which can still be inside the collapsing title region.
        collection.scrollToItem(at: IndexPath(item: 6, section: 0), at: .top, animated: false)
        try await BrowserNativeLayoutSettlement.wait(for: collection)
        let offset = collection.contentOffset
        XCTAssertGreaterThan(offset.y, -collection.adjustedContentInset.top + 1,
            "The strict preservation check must start in the list interior, not after native boundary clamping")

        if completion == .refresh {
            CompetitionBrowserPublicationAcceptance.refreshRequests.send(())
            try await waitForLocalization("browser.same_query_refresh_replacement_mounted") {
                displayed == [replacement.id] && publications.last == [replacement.id: replacement.name]
            }
        } else if completion == .filterABA {
            defaults.set("recent", forKey: "competition_filter_status")
            try await waitForLocalization("browser.aba_recent_rows_mounted") { displayed == [recent.id] }
            defaults.set("present", forKey: "competition_filter_status")
            try await waitForLocalization("browser.aba_present_replacement_mounted") {
                displayed == [replacement.id] && publications.last == [replacement.id: replacement.name]
            }
        }
        let beforeRelease = publications.count
        let displaysBeforeRelease = displayCount
        gate.release(completion == .unavailable || completion == .stale ? [:] : localizationNames(rows))
        if completion == .localized {
            let enrichedNames = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "Localized " + $0.name) })
            try await waitForLocalization("browser.name_cache_warm_without_native_row_replacement") {
                completedRequests.contains(rows.map(\.id))
            }
            let nextPresentation = await CompetitionService.localizeCompetitionNamesIfNeeded(rows,
                languageCode: "zh-Hans", cachedOnly: true)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: nextPresentation.map { ($0.id, $0.name) }), enrichedNames,
                "Next normal presentation can use localized names without another request")
            let restartedStore = CompetitionLocalizedNameStore(directory: directory)
            let persistedNames = await restartedStore.localizedCompetitionNames(cachedOnly: true) {
                XCTFail("Warm names must survive store recreation without network access")
                return [:]
            }
            XCTAssertEqual(persistedNames.mapValues(\.name), localizationNames(rows).mapValues(\.name))
            XCTAssertEqual(publications.last, canonicalNames)
            XCTAssertEqual(publications.count, beforeRelease)
            XCTAssertEqual(displayCount, displaysBeforeRelease)
            XCTAssertEqual(displayed, rows.map(\.id))
            XCTAssertTrue(localizationDescendants(window).contains { $0 === collection })
            XCTAssertEqual(dataSource.snapshot().itemIdentifiers, originalNativeIDs,
                "Optional name arrival must not replace currently presented native rows")
            XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 1, "Localization must not reset the native scroll owner")
            let nextHost = UIHostingController(rootView: CompatibleNavigationContainer {
                CompetitionBrowserView(isActive: true)
                    .environment(\.competitionBrowserPublicationEnabled, true)
                    .environment(\.competitionBrowserPublicationScope, scope)
            })
            let nextWindow = UIWindow(windowScene: scene)
            nextWindow.frame = window.frame; nextWindow.windowLevel = .alert + 2
            nextWindow.rootViewController = nextHost; nextWindow.makeKeyAndVisible()
            defer { nextWindow.isHidden = true; nextWindow.rootViewController = nil }
            try await waitForLocalization("browser.next_normal_load_uses_warmed_names") { publications.last == enrichedNames }
            XCTAssertEqual(collection.contentOffset.y, offset.y, accuracy: 1,
                "Preparing the next presentation must not mutate the original scroll owner")
        } else {
            try await waitForLocalization("browser.original_enrichment_finished_after_release") {
                completedRequests.contains(rows.map(\.id))
            }
            let keepsCanonical = completion == .unavailable || completion == .stale
            let expected = keepsCanonical ? canonicalNames : [replacement.id: replacement.name]
            XCTAssertEqual(publications.last, expected)
            XCTAssertTrue(publications.dropFirst(beforeRelease).allSatisfy { $0 == expected })
            XCTAssertEqual(displayed, keepsCanonical ? rows.map(\.id) : [replacement.id])
        }
        if completion == .stale {
            pendingPage?.resume(returning: CompetitionPageResult(competitions: [replacement], receivedCount: 1, nextPage: nil, totalCount: 1))
            pendingPage = nil
            try await waitForLocalization("browser.stale_cache_revalidation_replacement_mounted") { displayed == [replacement.id] }
        }
        XCTAssertEqual(pageRequests, completion == .refresh || completion == .stale ? 1 : 0)
        XCTAssertEqual(gate.requests, 1)
    }

    private func localizationRow(id: String, name: String, date: Date) -> CompetitionSummary {
        CompetitionSummary(id: id, name: name, shortDisplayName: nil, startDate: date, endDate: date,
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "Venue", venueAddress: "Address",
            venueDetails: nil, city: "Beijing", countryISO2: "CN", latitude: nil, longitude: nil,
            url: "https://www.worldcubeassociation.org/competitions/\(id)", website: "https://cubing.com/competition/\(id)",
            dateRange: "Fixture", eventIDs: ["333"], championshipTypes: nil, localizedRegionLineOverride: nil,
            localizedAddressLineOverride: nil, localizedStatusOverride: nil, localizedRegistrationStartOverride: nil,
            localizedWaitlistStartOverride: nil)
    }

    private func localizationNames(_ rows: [CompetitionSummary]) -> [String: LocalizedCompetitionInfo] {
        Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.id, LocalizedCompetitionInfo(slug: row.id, name: "Localized " + row.name, regionPrimary: nil,
                regionSecondary: nil, address: nil, registrationStart: nil, pauseRegistrationStart: nil,
                reopenRegistration: nil, registrationClose: nil))
        })
    }

    private func waitForLocalization(_ stage: String, file: StaticString = #filePath, line: UInt = #line,
                                     diagnostics: () -> String = { "" },
                                     _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for cached Browser localization [\(stage)]: \(diagnostics())", file: file, line: line)
        throw URLError(.timedOut)
    }

    private func localizationDescendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(localizationDescendants)
    }
}
