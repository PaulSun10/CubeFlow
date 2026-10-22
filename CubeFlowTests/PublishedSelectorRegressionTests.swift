import XCTest
import SwiftUI
@testable import CubeFlow

private actor PublishedMergeGate {
    private var blocked = true
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func merge(_ flags: [Int: PublishedRecordFlags], _ data: PublishedCompetitionData) async -> PublishedCompetitionData {
        calls += 1
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return PublishedCompetitionPR.applying(flags, to: data)
    }
    func release() { blocked = false; continuation?.resume(); continuation = nil }
}

private actor PublishedPersonalFlag {
    private var value = true
    func get() -> Bool { value }
    func retract() { value = false }
}

@MainActor final class PublishedSelectorRegressionTests: XCTestCase {
    private let own = "2020TEST01"
    private func row(_ id: Int = 1, person: String = "2020TEST01", round: String = "f", regional: String? = nil) -> PublishedCompetitionResult {
        .init(id: id, competitionID: "Test2025", eventID: "333fm", roundID: id, roundTypeID: round,
            formatID: "m", rank: 1, name: "Verified Person", wcaID: person, countryISO2: "CN",
            best: 25, average: 2700, attempts: [25, 27, 29], singleRecord: regional, averageRecord: nil)
    }
    nonisolated private static func page(personal: Bool = true) -> WCAPersonResultsPage {
        .init(contentLanguage: "en", summary: .init(region: "China", wcaId: "2020TEST01", gender: "Male", competitions: "1", completedSolves: "3"),
            previousIdentityText: nil, personalRecords: [], medalCollection: nil, recordCollection: nil,
            resultsSections: [.init(event: .init(code: "333fm", name: "3x3x3 Fewest Moves"), results: [
                .init(id: "provider-row", competitionName: "Test", competitionPath: "/competitions/Test2025",
                    countryISO2: "CN", roundName: "Final", place: "1", single: "25", average: "27.00", podiumPlace: nil,
                    singleEmphasis: personal ? .personalBest : nil, averageEmphasis: nil, solves: [])])])
    }
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 { if await predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Timed out waiting for published evidence")
    }
    func testOwnFMCFlagsPropagateToScopedSelectorsWithoutChangingGlobalDiscovery() {
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [row()])
        let single = PublishedCompetitionPR.applying([1: .init(single: true, average: false)], to: raw)
        XCTAssertEqual(single.results[0].singleBadge, "PR"); XCTAssertNil(single.results[0].averageBadge)
        XCTAssertEqual(single.selectorRecordTags(ownWCAID: own).events["333fm"], "PR")
        XCTAssertEqual(single.selectorRecordTags(ownWCAID: own).rounds[single.results[0].roundKey], "PR")
        XCTAssertTrue(single.eventRecordTags.isEmpty)
        let mean = PublishedCompetitionPR.applying([1: .init(single: false, average: true)], to: raw)
        XCTAssertNil(mean.results[0].singleBadge); XCTAssertEqual(mean.results[0].averageBadge, "PR")
        XCTAssertEqual(mean.selectorRecordTags(ownWCAID: own).events["333fm"], "PR")
        XCTAssertTrue(raw.selectorRecordTags(ownWCAID: own).events.isEmpty)
    }
    func testOtherPRMissingMalformedAndChangedIdentityFailClosed() {
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [row()])
        let data = PublishedCompetitionPR.applying([1: .init(single: true, average: true)], to: raw)
        for identity in [nil, "", "Verified Person", "12345", "2021TEST02"] as [String?] {
            XCTAssertTrue(data.selectorRecordTags(ownWCAID: identity).events.isEmpty)
            XCTAssertTrue(data.selectorRecordTags(ownWCAID: identity).rounds.isEmpty)
        }
        XCTAssertEqual(data.selectorRecordTags(ownWCAID: " 2020test01 ").events["333fm"], "PR")
    }
    func testRegionalPrecedenceAcrossRoundsAndOnlyOwnPRWithinRound() {
        for tag in ["NR", "AsR", "WR"] {
            let raw = PublishedCompetitionData(competitionID: "Test2025", results: [row(), row(2, person: "2021TEST02", round: "1", regional: tag)])
            let data = PublishedCompetitionPR.applying([1: .init(single: true, average: false)], to: raw)
            XCTAssertEqual(data.selectorRecordTags(ownWCAID: own).events["333fm"], PublishedCompetitionResult.recordBadge(tag))
            XCTAssertEqual(data.selectorRecordTags(ownWCAID: own).rounds[data.results[0].roundKey], "PR")
            XCTAssertEqual(data.selectorRecordTags(ownWCAID: nil).rounds[data.results[1].roundKey], PublishedCompetitionResult.recordBadge(tag))
        }
    }
    func testCancelledMergeCanPublishIdenticalCachedEvidenceOnReturn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { _, _ in Self.page() })
        let gate = PublishedMergeGate(), raw = PublishedCompetitionData(competitionID: "Test2025", results: [row()])
        let records = PublishedCompetitionRecordEnrichment(profiles: cache, merge: { await gate.merge($0, $1) })
        records.requested(own, source: raw)
        try await wait { await gate.calls == 1 }
        records.cancel(); await gate.release()
        XCTAssertNil(records.current(for: raw).results[0].singleBadge)
        records.requested(own, source: raw)
        try await wait { records.current(for: raw).results[0].singleBadge == "PR" }
        XCTAssertEqual(records.current(for: raw).selectorRecordTags(ownWCAID: own).events["333fm"], "PR")
        records.cancel()
    }
    func testMountedOwnEvidenceHydratesWithoutVisibleOwnRowOrNavigationAndSurvivesRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { _, _ in Self.page() })
        let records = PublishedCompetitionRecordEnrichment(profiles: cache)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results:
            (1...80).map { row($0, person: String(format: "2021TEST%02d", $0)) } + [row(1000)])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        func content() -> some View {
            ScrollView {
                PublishedCompetitionResultsContent(data: raw, language: "en", recordEnrichment: records)
                    .environment(\.competitionLivePreviewIdentity, own)
            }
        }
        window.rootViewController = UIHostingController(rootView: content()); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; records.cancel() }
        try await wait { records.current(for: raw).selectorRecordTags(ownWCAID: own).events["333fm"] == "PR" }
        window.rootViewController = UIHostingController(rootView: Color.clear)
        for _ in 0..<10 { await Task.yield() }
        window.rootViewController = UIHostingController(rootView: content())
        XCTAssertEqual(records.current(for: raw).selectorRecordTags(ownWCAID: own).events["333fm"], "PR")
    }
    func testExplicitRefreshRetractsCachedOwnEvidenceEvenWhenOwnRowWasNeverVisible() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let flag = PublishedPersonalFlag()
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { _, _ in Self.page(personal: await flag.get()) })
        _ = try await cache.page(own, language: "en")
        let records = PublishedCompetitionRecordEnrichment(profiles: cache)
        let raw = PublishedCompetitionData(competitionID: "Test2025", results: [row()])
        records.requested(own, source: raw)
        try await wait { records.current(for: raw).selectorRecordTags(ownWCAID: own).events["333fm"] == "PR" }
        await flag.retract()
        records.refreshVisible(including: own)
        try await wait { records.current(for: raw).selectorRecordTags(ownWCAID: own).events.isEmpty }
        XCTAssertNil(records.current(for: raw).results[0].singleBadge)
        records.cancel()
    }
}
