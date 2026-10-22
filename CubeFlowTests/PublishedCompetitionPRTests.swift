import XCTest
import SwiftUI
@testable import CubeFlow

private actor PublishedPRProbe {
    var personal = true
    var fail = false
    private var blocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    func configure(personal: Bool = true, fail: Bool = false, blocked: Bool = false) {
        self.personal = personal; self.fail = fail; self.blocked = blocked
    }
    func release() { blocked = false; waiters.forEach { $0.resume() }; waiters = [] }
    func load() async throws -> Bool {
        calls += 1
        if blocked { await withCheckedContinuation { waiters.append($0) } }
        try Task.checkCancellation()
        if fail { throw URLError(.notConnectedToInternet) }
        return personal
    }
}

@MainActor final class PublishedCompetitionPRTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        super.setUp(); directory = FileManager.default.temporaryDirectory.appendingPathComponent("published-pr-" + UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory); super.tearDown() }
    private func result(_ id: Int = 1, person: String = "2020TEST01", event: String = "333", round: String = "f",
                        single: String? = nil, average: String? = nil) -> PublishedCompetitionResult {
        .init(id: id, competitionID: "Test2025", eventID: event, roundID: id, roundTypeID: round, formatID: "a",
            rank: 1, name: "Public Fixture", wcaID: person, countryISO2: "CN", best: 900, average: 1000,
            attempts: [900, 1000, 1000, 1000, 1100], singleRecord: single, averageRecord: average)
    }
    nonisolated private static func page(_ id: String = "2020TEST01", single: Bool = true, average: Bool = true,
                                        competition: String = "Test2025", round: String = "Final", score: String = "9.00") -> WCAPersonResultsPage {
        let row = WCACompetitionResult(id: "profile-row", competitionName: "Test Open", competitionPath: "/competitions/\(competition)",
            countryISO2: "CN", roundName: round, place: "1", single: score, average: "10.00", podiumPlace: nil,
            singleEmphasis: single ? .personalBest : nil, averageEmphasis: average ? .personalBest : nil, solves: [])
        return WCAPersonResultsPage(contentLanguage: "en", summary: .init(region: "China", wcaId: id, gender: "Male", competitions: "1", completedSolves: "5"),
            previousIdentityText: nil, personalRecords: [], medalCollection: nil, recordCollection: nil,
            resultsSections: [.init(event: .init(code: "333", name: "3x3x3 Cube"), results: [row])])
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 { if await condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Timed out waiting for production record enrichment")
    }
    func testOfficialJSONDoesNotInventPRButAuthoritativePBCellsRestoreBothAdapters() throws {
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        XCTAssertNil(raw.results[0].singleBadge); XCTAssertNil(raw.results[0].averageBadge)
        let flags = PublishedCompetitionPR.flags(page: Self.page(), data: raw)
        let data = PublishedCompetitionPR.applying(flags, to: raw)
        XCTAssertEqual(data.results[0].singleBadge, "PR"); XCTAssertEqual(data.results[0].averageBadge, "PR")
        let preview = PublishedCompetitionPresentation.preview(data.results[0], language: "en")
        XCTAssertEqual(preview.singleRecordTag, "PR"); XCTAssertEqual(preview.averageRecordTag, "PR")
        let all = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2020TEST01", data: data, language: "en")?.results.first)
        XCTAssertEqual(all.singleRecordTag, "PR"); XCTAssertEqual(all.averageRecordTag, "PR")
        XCTAssertEqual(raw.results[0].best, data.results[0].best); XCTAssertEqual(raw.results[0].attempts, data.results[0].attempts)
        XCTAssertNil(data.eventRecordTags["333"], "A personal record must never become a global regional record")
    }
    func testSingleAverageAndRegionalRecordsRemainSeparate() {
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result(single: "AsR")])
        let singleOnly = PublishedCompetitionPR.applying(PublishedCompetitionPR.flags(page: Self.page(single: true, average: false), data: raw), to: raw)
        XCTAssertEqual(singleOnly.results[0].singleBadge, "CR"); XCTAssertNil(singleOnly.results[0].averageBadge)
        let averageOnly = PublishedCompetitionPR.applying(PublishedCompetitionPR.flags(page: Self.page(single: false, average: true), data: raw), to: raw)
        XCTAssertEqual(averageOnly.results[0].singleBadge, "CR"); XCTAssertEqual(averageOnly.results[0].averageBadge, "PR")
        let retracted = PublishedCompetitionPR.applying(PublishedCompetitionPR.flags(page: Self.page(single: false, average: false), data: raw), to: averageOnly)
        XCTAssertNil(retracted.results[0].averageBadge); XCTAssertEqual(retracted.results[0].singleBadge, "CR")
    }
    func testMountedOfficialEvidenceUpdatesOpenSummaryAndAllResultsWithoutResettingExpansion() async throws {
        let profiles = WCAPublicProfileCache(directory: directory, pageLoader: { id, _ in Self.page(id) })
        let records = PublishedCompetitionRecordEnrichment(profiles: profiles)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        let sourceRound = try XCTUnwrap(raw.rounds.first)
        let round = PublishedCompetitionPresentation.round(sourceRound, language: "en", data: raw)
        let card = CompetitionResultCardState()
        card.present(result: try XCTUnwrap(round.results.first), round: round, isPublished: true,
            initialContent: PublishedCompetitionPresentation.competitor("2020TEST01", data: raw, language: "en"), loader: nil)
        card.resultSummaryHeight = 150; card.allResultsHeight = 270
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: PublishedCompetitionResultsContent(data: raw, language: "en",
            resultCard: card, recordEnrichment: records))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; records.cancel() }
        try await wait { card.selection?.result.singleRecordTag == "PR" }
        XCTAssertEqual(card.selection?.result.averageRecordTag, "PR")
        XCTAssertEqual(card.selectedCompetitorContent?.results.first?.singleRecordTag, "PR")
        XCTAssertEqual(card.selectedCompetitorContent?.results.first?.averageRecordTag, "PR")
        XCTAssertEqual(card.resultSummaryHeight, 150); XCTAssertEqual(card.allResultsHeight, 270)
        XCTAssertEqual(card.selection?.result.attempts, raw.results[0].performedAttempts)
        card.refreshPublishedRecordEvidence(raw, language: "en")
        XCTAssertNil(card.selection?.result.singleRecordTag)
        XCTAssertNil(card.selectedCompetitorContent?.results.first?.averageRecordTag)
        XCTAssertEqual(card.allResultsHeight, 270)
    }
    func testEvidenceRequiresExactCompetitionPersonEventRoundAndMatchingResultIdentity() {
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page("2021TEST02"), data: raw).isEmpty)
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page(competition: "Other2025"), data: raw).isEmpty)
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page(round: "First round"), data: raw).isEmpty)
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page(score: "8.00"), data: raw).isEmpty)
        let wrongEvent = PublishedCompetitionData(competitionID: "Test2025", results: [result(event: "222")])
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page(), data: wrongEvent).isEmpty)
        let ambiguous = PublishedCompetitionData(competitionID: "Test2025", results: [result(), result(2)])
        XCTAssertTrue(PublishedCompetitionPR.flags(page: Self.page(), data: ambiguous).isEmpty)
    }
    func testVisibleProfileLoadingIsConcurrencyLimitedAndRetractsWithoutChangingNumbers() async throws {
        let probe = PublishedPRProbe(); await probe.configure(blocked: true)
        let profiles = WCAPublicProfileCache(directory: directory, pageLoader: { id, _ in
            let personal = try await probe.load()
            return Self.page(id, single: personal, average: personal)
        })
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: (1...8).map { result($0, person: String(format: "2020TEST%02d", $0)) })
        let store = PublishedCompetitionRecordEnrichment(profiles: profiles)
        for row in raw.results { store.appeared(row.wcaID, source: raw) }
        try await wait { await probe.calls == 4 }
        let count = await probe.calls; XCTAssertEqual(count, 4)
        await probe.release()
        try await wait { store.current(for: raw).results.allSatisfy { $0.singleBadge == "PR" && $0.averageBadge == "PR" } }
        await probe.configure(personal: false)
        store.refreshVisible()
        try await wait { store.current(for: raw).results.allSatisfy { $0.singleBadge == nil && $0.averageBadge == nil } }
        XCTAssertEqual(store.current(for: raw).results.map(\.best), raw.results.map(\.best))
        store.cancel()
    }
    func testRestartOfflineUsesDatedServerMarkersRatherThanNumericalInference() async throws {
        let old = Date().addingTimeInterval(-1000), directory = directory!
        let seed = WCAPublicProfileCache(directory: directory, now: { old }, pageLoader: { id, _ in Self.page(id) })
        _ = try await seed.page("2020TEST01", language: "en")
        let offline = WCAPublicProfileCache(directory: directory, pageLoader: { _, _ in throw URLError(.notConnectedToInternet) })
        let store = PublishedCompetitionRecordEnrichment(profiles: offline)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        store.appeared("2020TEST01", source: raw)
        try await wait { store.current(for: raw).results.first?.singleBadge == "PR" && store.showsSavedEvidence }
        XCTAssertTrue(store.showsSavedEvidence)
        store.refreshVisible()
        XCTAssertEqual(store.current(for: raw).results.first?.singleBadge, "PR")
        store.cancel()
    }

    func testStaleCacheIsQuietWhileOnlineRefreshIsPendingAndSuccessKeepsPR() async throws {
        let old = Date().addingTimeInterval(-1000), directory = directory!
        let seed = WCAPublicProfileCache(directory: directory, now: { old }, pageLoader: { id, _ in Self.page(id) })
        _ = try await seed.page("2020TEST01", language: "en")
        let probe = PublishedPRProbe(); await probe.configure(blocked: true)
        let profiles = WCAPublicProfileCache(directory: directory, pageLoader: { id, _ in
            _ = try await probe.load(); return Self.page(id)
        })
        let store = PublishedCompetitionRecordEnrichment(profiles: profiles)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        defer { store.cancel() }
        store.appeared("2020TEST01", source: raw)
        try await wait { await probe.calls == 1 && store.current(for: raw).results.first?.singleBadge == "PR" }
        XCTAssertFalse(store.showsSavedEvidence, "Stale-while-revalidate is not an offline/failure state")
        await probe.release()
        try await wait { await profiles.cachedPage("2020TEST01", language: "en")?.lastUpdated ?? .distantPast > old }
        XCTAssertFalse(store.showsSavedEvidence)
        XCTAssertEqual(store.current(for: raw).results.first?.singleBadge, "PR")
    }

    func testFailedForcedRefreshShowsSavedEvidenceAndFreshSuccessClearsIt() async throws {
        let probe = PublishedPRProbe()
        let profiles = WCAPublicProfileCache(directory: directory, pageLoader: { id, _ in
            _ = try await probe.load(); return Self.page(id)
        })
        let store = PublishedCompetitionRecordEnrichment(profiles: profiles)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        defer { store.cancel() }
        store.appeared("2020TEST01", source: raw)
        try await wait { store.current(for: raw).results.first?.averageBadge == "PR" }
        XCTAssertFalse(store.showsSavedEvidence)
        await probe.configure(fail: true)
        store.refreshVisible()
        try await wait { store.showsSavedEvidence }
        XCTAssertEqual(store.current(for: raw).results.first?.singleBadge, "PR")
        await probe.configure()
        store.refreshVisible()
        try await wait { !store.showsSavedEvidence }
        XCTAssertEqual(store.current(for: raw).results.first?.averageBadge, "PR")
    }

    func testFreshCacheReuseIsQuietAndDoesNotDownloadAgain() async throws {
        let probe = PublishedPRProbe()
        let profiles = WCAPublicProfileCache(directory: directory, pageLoader: { id, _ in
            _ = try await probe.load(); return Self.page(id)
        })
        _ = try await profiles.page("2020TEST01", language: "en")
        let store = PublishedCompetitionRecordEnrichment(profiles: profiles)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [result()])
        defer { store.cancel() }
        store.appeared("2020TEST01", source: raw)
        try await wait { store.current(for: raw).results.first?.singleBadge == "PR" }
        XCTAssertFalse(store.showsSavedEvidence)
        let calls = await probe.calls; XCTAssertEqual(calls, 1)
    }
}
