import XCTest
@testable import CubeFlow

private actor ParticipationLoaderProbe {
    private(set) var count = 0
    var continuation: CheckedContinuation<Void, Never>?
    let blocked: Bool
    init(blocked: Bool = false) { self.blocked = blocked }
    func request() async {
        count += 1
        if blocked { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class WCAOfficialParticipationTests: XCTestCase {
    nonisolated private static func page(_ id: String) -> WCAPersonResultsPage {
        let rows = ["/competitions/Official2026", "/competitions/Official2026", "https://www.worldcubeassociation.org/competitions/Another2026", "https://untrusted.invalid/competitions/Fake2026"].enumerated().map { index, path in
            WCACompetitionResult(id: String(index), competitionName: "Fixture", competitionPath: path,
                countryISO2: "US", roundName: "Final", place: "1", single: "DNF", average: nil,
                podiumPlace: nil, singleEmphasis: nil, averageEmphasis: nil, solves: [])
        }
        return .init(contentLanguage: "en", summary: .init(region: "USA", wcaId: id,
            gender: "Male", competitions: "2", completedSolves: "5"), previousIdentityText: nil,
            personalRecords: [], medalCollection: nil, recordCollection: nil,
            resultsSections: [.init(event: .init(code: "333", name: "3x3x3 Cube"), results: rows)])
    }

    func testOfficialRowsOnlyAndIdentityIsRequired() {
        let page = Self.page("2020TEST01")
        XCTAssertEqual(WCAOfficialParticipation.competitionIDs(page: page, wcaID: "2020TEST01"), ["Official2026", "Another2026"])
        XCTAssertTrue(WCAOfficialParticipation.competitionIDs(page: page, wcaID: "2021OTHER01").isEmpty)
        XCTAssertTrue(WCAOfficialParticipation.competitionIDs(page: page, wcaID: "").isEmpty)
    }

    func testProductionViewModelReusesPublicCacheAndDoesNotScanCompetitions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = ParticipationLoaderProbe()
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { id, _ in
            await probe.request(); return Self.page(id)
        })
        let viewModel = WCAMyCompetitionsViewModel()
        await viewModel.loadParticipation(wcaID: "2020TEST01", profiles: cache)
        XCTAssertEqual(viewModel.participatedCompetitionIDs, ["Official2026", "Another2026"])
        await viewModel.loadParticipation(wcaID: "2020TEST01", profiles: cache)
        let count = await probe.count
        XCTAssertEqual(count, 1)
        await viewModel.loadParticipation(wcaID: nil, profiles: cache)
        XCTAssertTrue(viewModel.participatedCompetitionIDs.isEmpty)
    }

    func testDelayedOldAccountCannotPublishAfterIdentityIsCleared() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = ParticipationLoaderProbe(blocked: true)
        let cache = WCAPublicProfileCache(directory: root, pageLoader: { id, _ in
            await probe.request(); return Self.page(id)
        })
        let viewModel = WCAMyCompetitionsViewModel()
        let task = Task { await viewModel.loadParticipation(wcaID: "2020TEST01", profiles: cache) }
        for _ in 0..<200 {
            if await probe.count > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await viewModel.loadParticipation(wcaID: nil, profiles: cache)
        await probe.release(); await task.value
        XCTAssertTrue(viewModel.participatedCompetitionIDs.isEmpty)
    }
}

@MainActor final class WCAMyCompetitionsLoadingTests: XCTestCase {
    private func page(_ id: String) -> WCAMyCompetitionsPage {
        .init(futureCompetitions: [.init(id: id, name: id, website: nil, startDate: nil,
            endDate: nil, registrationOpen: nil, url: nil, city: nil, countryISO2: nil,
            shortDisplayName: nil, registrationStatus: nil)], pastCompetitions: [],
            bookmarkedCompetitions: [], registrationsByCompetition: [:])
    }

    func testCancellationWhileResolvingNamesClearsLoadingWithoutPublishing() async throws {
        let model = WCAMyCompetitionsViewModel()
        let waiting = expectation(description: "Localized name request started")
        var reply: CheckedContinuation<[String: String], Never>?
        let load = Task {
            await model.load(fetchPage: { self.page("Old2026") }, resolveNames: { _, _ in
                await withCheckedContinuation { reply = $0; waiting.fulfill() }
            })
        }
        await fulfillment(of: [waiting], timeout: 3)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.page, "Do not briefly publish an unlocalized page while names are loading")
        load.cancel()
        try XCTUnwrap(reply).resume(returning: ["Old2026": "Old localized name"])
        await load.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.page)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.localizedNames.isEmpty)
    }

    func testNewRefreshOwnsPageAndLoadingWhileOldNamesFinishLate() async throws {
        let model = WCAMyCompetitionsViewModel()
        let oldWaiting = expectation(description: "Old name request started")
        let newWaiting = expectation(description: "New name request started")
        var oldReply: CheckedContinuation<[String: String], Never>?
        var newReply: CheckedContinuation<[String: String], Never>?
        let oldLoad = Task {
            await model.load(fetchPage: { self.page("Old2026") }, resolveNames: { _, _ in
                await withCheckedContinuation { oldReply = $0; oldWaiting.fulfill() }
            })
        }
        await fulfillment(of: [oldWaiting], timeout: 3)
        let refresh = Task {
            await model.load(forceRefresh: true, fetchPage: { self.page("New2026") }, resolveNames: { _, _ in
                await withCheckedContinuation { newReply = $0; newWaiting.fulfill() }
            })
        }
        await fulfillment(of: [newWaiting], timeout: 3)
        try XCTUnwrap(oldReply).resume(returning: ["Old2026": "Old localized name"])
        await oldLoad.value
        XCTAssertTrue(model.isLoading, "An obsolete load cannot clear the newer loading state")
        XCTAssertNil(model.page)
        XCTAssertTrue(model.localizedNames.isEmpty)
        try XCTUnwrap(newReply).resume(returning: ["New2026": "New localized name"])
        await refresh.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.page?.futureCompetitions.map(\.id), ["New2026"])
        XCTAssertEqual(model.localizedNames, ["New2026": "New localized name"])
    }
}
