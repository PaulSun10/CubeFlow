import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct ExploreRecentRecordStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func emptyFailureAndSavedRecordsRemainDistinct() async throws {
        let record = try fixtureRecord()
        for (records, fails, expected) in [
            ([WCARecentRecord](), false, ExploreLoadState.empty),
            ([], true, .failed),
            ([record], true, .failedWithCache),
            ([record], false, .loaded)
        ] {
            let provider = RecordStateProvider(snapshot: ExploreRecentRecordsSnapshot(records: records,
                fetchedAt: now.addingTimeInterval(-3600)), fails: fails)
            let store = ExploreStore(recentRecordsProvider: provider)
            await store.loadRecentRecords(language: "en", force: true, now: now)
            #expect(store.recordsState == expected)
            #expect(store.recentRecordItems.count == records.count)
            #expect(store.recentRecordItems.first?.result?.level == records.first.map { _ in .world })
        }
    }

    @Test func languageChangeDuringInitialRequestUsesLatestLanguageAndCoalescesTraffic() async throws {
        let record = try fixtureRecord()
        let provider = SuspendedRecordProvider()
        let store = ExploreStore(recentRecordsProvider: provider)
        let request = Task { await store.loadRecentRecords(language: "en", force: true, now: now) }
        await provider.waitUntilStarted()
        #expect(store.recordsState == .loading)
        await store.loadRecentRecords(language: "zh-Hans", force: true, now: now)
        provider.finish(ExploreRecentRecordsSnapshot(records: [record], fetchedAt: now))
        await request.value
        #expect(provider.calls == 1)
        #expect(store.recordsState == .loaded)
        let context = try #require(store.recentRecordItems.first?.recordContext)
        #expect(context.eventName == CompetitionEventPresentation.localizedFullName(for: "333", languageCode: "zh-Hans"))
        #expect(context.resultType == appLocalizedString("explore.public.single", languageCode: "zh-Hans", tableName: "ExplorePublicData"))
        #expect(store.recentRecordItems.count == 1)
        #expect(store.recentRecordItems.first?.result?.currentRank == nil)
    }

    private func fixtureRecord() throws -> WCARecentRecord {
        try JSONDecoder().decode(WCARecentRecord.self, from: Data("""
        {"id":"fixture-single","tag":"WR","type":"single","attemptResult":274,
        "result":{"id":"fixture-result","person":{"id":"1","wcaId":"2020TEST01","name":"Fixture Cuber",
        "country":{"iso2":"US","name":"United States"}},"round":{"id":"fixture-round",
        "competitionEvent":{"event":{"id":"333","name":"3x3x3 Cube"},
        "competition":{"id":"1","wcaId":"Fixture2026","name":"Fixture Open"}}}}}
        """.utf8))
    }
}

@MainActor
private struct RecordStateProvider: ExploreRecentRecordsProviding {
    let snapshot: ExploreRecentRecordsSnapshot
    let fails: Bool
    func cached() async -> ExploreRecentRecordsSnapshot? { snapshot }
    func refresh() async throws -> ExploreRecentRecordsSnapshot {
        if fails { throw URLError(.notConnectedToInternet) }
        return snapshot
    }
}

@MainActor
private final class SuspendedRecordProvider: ExploreRecentRecordsProviding {
    private var completion: CheckedContinuation<ExploreRecentRecordsSnapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func cached() async -> ExploreRecentRecordsSnapshot? { nil }
    func refresh() async throws -> ExploreRecentRecordsSnapshot {
        calls += 1
        return await withCheckedContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ value: ExploreRecentRecordsSnapshot) {
        completion?.resume(returning: value)
        completion = nil
    }
}
