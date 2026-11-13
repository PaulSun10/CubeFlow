import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class PostDeviceUXTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func row() -> CompetitionSummary {
        CompetitionSummary(id: "PostDeviceFixture2026", name: "Official Name", shortDisplayName: nil,
            startDate: Date(), endDate: Date(), registrationOpen: nil, registrationClose: nil, competitorLimit: nil,
            venue: "Venue", venueAddress: "Address", venueDetails: nil, city: "Beijing", countryISO2: "CN",
            latitude: nil, longitude: nil, url: "https://www.worldcubeassociation.org/competitions/PostDeviceFixture2026",
            website: nil, dateRange: "2026", eventIDs: ["333"], championshipTypes: nil,
            localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }

    func testSharedNameCacheServesAccountAndDiscoveryWithoutNetworkOrChinaWebsiteRequirement() async throws {
        let previous = CompetitionService.localizedCompetitionNamesForTesting
        let store = CompetitionLocalizedNameStore(directory: directory)
        let item = row()
        await store.merge([item.id.lowercased(): .init(slug: "fixture", name: "中文比賽名稱", regionPrimary: nil,
            regionSecondary: nil, address: nil, registrationStart: nil, pauseRegistrationStart: nil,
            reopenRegistration: nil, registrationClose: nil)])
        CompetitionService.localizedCompetitionNamesForTesting = (store, { _ in XCTFail("Cache hit must not fetch"); return [:] })
        defer { CompetitionService.localizedCompetitionNamesForTesting = previous }
        for language in ["zh-Hans", "zh-Hant"] {
            let localized = await CompetitionService.localizeCompetitionNamesIfNeeded([item], languageCode: language, cachedOnly: true)
            let names = await CompetitionService.localizedCompetitionDisplayNames([.init(id: item.id, name: item.name, website: nil)], languageCode: language)
            XCTAssertEqual(localized.first?.name, language == "zh-Hans" ? "中文比赛名称" : "中文比賽名稱")
            XCTAssertEqual(names[item.id], localized.first?.name)
        }
        let english = await CompetitionService.localizeCompetitionNamesIfNeeded([item], languageCode: "en", cachedOnly: true)
        let names = await CompetitionService.localizedCompetitionDisplayNames([.init(id: item.id, name: item.name, website: nil)], languageCode: "en")
        XCTAssertEqual(english.first?.name, item.name); XCTAssertTrue(names.isEmpty)
        let urlNames = await CompetitionService.localizedCompetitionDisplayNames([
            .init(id: "OTHER", name: "Different", website: "https://www.worldcubeassociation.org/competitions/POSTDEVICEFIXTURE2026?lang=en#info")], languageCode: "zh-Hans")
        XCTAssertEqual(urlNames["OTHER"], "中文比赛名称", "URL suffixes and case must use the same canonical lookup key")
    }

    func testSuccessfulSummaryPersistsForOfflineReopeningAndDoesNotInventUnknownCompetition() async throws {
        let previous = CompetitionService.competitionSummaryLoaderForTesting
        defer { CompetitionService.competitionSummaryLoaderForTesting = previous }
        let item = row(), cache = CompetitionSummaryCache(directory: directory)
        CompetitionService.competitionSummaryLoaderForTesting = { _, _ in item }
        let fetched = try await CompetitionService.fetchCompetitionSummary(id: item.id, languageCode: "en", cache: cache)
        XCTAssertEqual(fetched.id, item.id)
        CompetitionService.competitionSummaryLoaderForTesting = { _, _ in throw URLError(.notConnectedToInternet) }
        let restored = CompetitionSummaryCache(directory: directory)
        let offline = await CompetitionService.cachedCompetitionSummary(id: item.id, languageCode: "en", cache: restored)
        XCTAssertEqual(offline?.name, item.name)
        do { _ = try await CompetitionService.fetchCompetitionSummary(id: item.id, languageCode: "en", cache: restored); XCTFail("Revalidation must report failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let retained = await restored.summary(item.id), absent = await restored.summary("Uncached")
        XCTAssertEqual(retained?.name, item.name); XCTAssertNil(absent)
        let expired = CompetitionSummaryCache(directory: directory, now: { Date().addingTimeInterval(31 * 86400) })
        let old = await expired.summary(item.id); XCTAssertNil(old)
    }

    func testIndependentSummaryRetentionDoesNotEvictQuerySnapshots() async throws {
        let cache = CompetitionQueryCacheStore(directory: directory)
        await cache.store(.init(competitions: [row()], totalCount: 1, lastUpdated: Date()), for: "browser")
        let lookup = await cache.summary(for: row().id)
        XCTAssertEqual(lookup?.name, row().name)
        let restored = CompetitionQueryCacheStore(directory: directory)
        let disk = await restored.summary(for: row().id); XCTAssertEqual(disk?.id, row().id)
    }

    func testAlreadyPersistedDetailTitleBecomesAvailableToAccountNamePresentationOffline() async throws {
        let previous = CompetitionService.localizedCompetitionNamesForTesting
        CompetitionService.localizedCompetitionNamesForTesting = (CompetitionLocalizedNameStore(directory: directory),
            { _ in XCTFail("Previously loaded title must not need network enrichment"); return [:] })
        defer { CompetitionService.localizedCompetitionNamesForTesting = previous }
        let item = row(), key = "section-v2|wca|\(row().id)|zh-Hant|info"
        var content = CompetitionDetailContent.empty
        content.localizedName = "已載入的中文名稱"; content.wcaCompetitionID = item.id
        await CompetitionDetailContentStore.shared.store(content, for: key)
        let cached = await CompetitionService.cachedCompetitionResourceSnapshot(.info, for: item, languageCode: "zh-Hant")
        let names = await CompetitionService.localizedCompetitionDisplayNames([.init(id: item.id, name: item.name, website: nil)], languageCode: "zh-Hant")
        XCTAssertEqual(cached?.content.localizedName, names[item.id])
        XCTAssertEqual(names[item.id], "已載入的中文名稱")
        await CompetitionDetailContentStore.shared.remove(key: key)
    }

    func testInFlightCatalogueCannotOverwriteNewerKnownDetailName() async throws {
        let store = CompetitionLocalizedNameStore(directory: directory), gate = PostDeviceNameGate()
        let old = LocalizedCompetitionInfo(slug: nil, name: "Old", regionPrimary: nil, regionSecondary: nil,
            address: nil, registrationStart: nil, pauseRegistrationStart: nil, reopenRegistration: nil, registrationClose: nil)
        let newer = LocalizedCompetitionInfo(slug: nil, name: "New", regionPrimary: nil, regionSecondary: nil,
            address: nil, registrationStart: nil, pauseRegistrationStart: nil, reopenRegistration: nil, registrationClose: nil)
        let pending = Task { await store.localizedCompetitionNames { await gate.load() } }
        for _ in 0..<1000 { if await gate.waiting { break }; await Task.yield() }
        let waiting = await gate.waiting; XCTAssertTrue(waiting)
        await store.merge(["known": newer])
        await gate.release(["known": old, "other": old])
        let completed = await pending.value
        XCTAssertEqual(completed["known"]?.name, "New"); XCTAssertEqual(completed["other"]?.name, "Old")
        let restored = CompetitionLocalizedNameStore(directory: directory)
        let disk = await restored.localizedCompetitionNames(cachedOnly: true) { XCTFail("Must be persisted"); return [:] }
        XCTAssertEqual(disk["known"]?.name, "New"); XCTAssertEqual(disk["other"]?.name, "Old")
    }

    func testTrendPresentationRendersEmptySingleAndDenseDataInBothModesAndAppearances() async throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let format = appLocalizedString("data.trend.solve_count", languageCode: language)
            XCTAssertTrue(format.contains("%d"), "The localized count must remain a format, not a hardcoded number")
            XCTAssertTrue(String(format: format, 2000).contains("2000"))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for mode in TrendMode.allCases {
            for dark in [false, true] {
                for count in [0, 1, 2000] {
                    let solves = (0..<count).map { index in
                        SessionSolveSample(id: UUID(), date: Date(timeIntervalSince1970: Double(index * 3600)),
                            time: 8 + Double(index % 23) / 10, resultRaw: "solved", scramble: "R U", comment: "", eventRawValue: "3x3")
                    }
                    let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 740)
                    window.overrideUserInterfaceStyle = dark ? .dark : .light
                    let host = UIHostingController(rootView: TimeTrendSheet(solves: solves, appLanguage: "en", initialMode: mode))
                    window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
                    defer { window.isHidden = true; window.rootViewController = nil }
                    try await Task.sleep(nanoseconds: 150_000_000)
                    window.layoutIfNeeded(); host.view.layoutIfNeeded()
                    XCTAssertEqual(host.view.bounds.width, 393, accuracy: 1)
                    let snapshot = SessionSolveTrend(solves: solves)
                    XCTAssertEqual(snapshot.points.count, count)
                    if count == 2000 {
                        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                            .appendingPathComponent("build/post-device-ux-nov02/chart-\(mode.rawValue)-\(dark ? "dark" : "light").png")
                        try image.pngData()?.write(to: url)
                    }
                }
            }
        }
    }
}

private actor PostDeviceNameGate {
    private var continuation: CheckedContinuation<[String: LocalizedCompetitionInfo], Never>?
    private var response: [String: LocalizedCompetitionInfo]?
    var waiting: Bool { continuation != nil }
    func load() async -> [String: LocalizedCompetitionInfo] {
        if let response { return response }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: [String: LocalizedCompetitionInfo]) {
        response = value; continuation?.resume(returning: value); continuation = nil
    }
}
